CloudFormation do
  
  ecs_tags = []
  ecs_tags << { Key: 'Name', Value: FnSub("${EnvironmentName}-#{component_name}") }
  ecs_tags << { Key: 'EnvironmentName', Value: Ref(:EnvironmentName) }
  ecs_tags << { Key: 'EnvironmentType', Value: Ref(:EnvironmentType) }
  
  ECS_Cluster(:EcsCluster) {
    ClusterName FnSub(cluster_name) if defined? cluster_name
    ClusterSetting({ Name: 'containerInsights', Value: Ref(:ContainerInsights) })
    Tags ecs_tags
  }
  
  Output(:EcsCluster) {
    Value(Ref(:EcsCluster))
    Export FnSub("${EnvironmentName}-#{component_name}-EcsCluster")
  }
  
  Output(:EcsClusterArn) {
    Value(FnGetAtt('EcsCluster','Arn'))
    Export FnSub("${EnvironmentName}-#{component_name}-EcsClusterArn")
  }
  
  unless fargate_only_cluster
    
    Condition(:SpotEnabled, FnEquals(Ref(:Spot), 'true'))
    Condition(:KeyPairSet, FnNot(FnEquals(Ref(:KeyPair), '')))
    
    ip_blocks = {} unless defined? ip_blocks
    
    EC2_SecurityGroup(:SecurityGroupEcs) {
      VpcId Ref(:VPCId)
      GroupDescription FnSub("${EnvironmentName}-#{component_name}")
      
      if defined? security_group_rules
        SecurityGroupIngress generate_security_group_rules(security_group_rules,ip_blocks)
      end
      
      Tags ecs_tags
    }
  
    IAM_Role(:Role) {
      Path '/'
      AssumeRolePolicyDocument service_assume_role_policy('ec2')
      Policies iam_role_policies(iam_policies)
      Tags ecs_tags
    }
    
    InstanceProfile(:InstanceProfile) {
      Path '/'
      Roles [Ref(:Role)]
    }
    
    instance_userdata = <<~USERDATA
    #!/bin/bash
    iptables --insert FORWARD 1 --in-interface docker+ --destination 169.254.169.254/32 --jump DROP
    service iptables save
    echo ECS_CLUSTER=${EcsCluster} >> /etc/ecs/ecs.config
    USERDATA
    
    if defined? ecs_agent_config
      instance_userdata += ecs_agent_config.map { |k,v| "echo #{k}=#{v} >> /etc/ecs/ecs.config" }.join('\n')
    end
    
    if defined? userdata
      instance_userdata += userdata
    end
    
    ecs_instance_tags = ecs_tags.map(&:clone)
    ecs_instance_tags.push({ Key: 'Role', Value: 'ecs' })
    ecs_instance_tags.push({ Key: 'Name', Value: FnSub("${EnvironmentName}-ecs-xx") })
    ecs_instance_tags.push(*instance_tags.map {|k,v| {Key: k, Value: FnSub(v)}}) if defined? instance_tags
    
    template_data = {
        SecurityGroupIds: [ Ref(:SecurityGroupEcs) ],
        TagSpecifications: [
          { ResourceType: 'instance', Tags: ecs_instance_tags },
          { ResourceType: 'volume', Tags: ecs_instance_tags }
        ],
        UserData: FnBase64(FnSub(instance_userdata)),
        IamInstanceProfile: { Name: Ref(:InstanceProfile) },
        KeyName: FnIf(:KeyPairSet, Ref(:KeyPair), Ref('AWS::NoValue')),
        ImageId: Ref(:Ami),
        InstanceType: Ref(:InstanceType)
    }

    spot_options = {
      MarketType: 'spot',
      SpotOptions: {
        SpotInstanceType: 'one-time',
      }
    }
    template_data[:InstanceMarketOptions] = FnIf(:SpotEnabled, spot_options, Ref('AWS::NoValue'))

    if defined? volumes
      template_data[:BlockDeviceMappings] = volumes
    end
    
    EC2_LaunchTemplate(:LaunchTemplate) {
      LaunchTemplateData(template_data)
    }
    
    ecs_asg_tags = ecs_tags.map(&:clone)

    AutoScaling_AutoScalingGroup(:AutoScaleGroup) {
      UpdatePolicy(:AutoScalingReplacingUpdate, {
        WillReplace: true
      })
      UpdatePolicy(:AutoScalingScheduledAction, {
        IgnoreUnmodifiedGroupSizeProperties: true
      })
      DesiredCapacity Ref(:AsgDesired)
      MinSize Ref(:AsgMin)
      MaxSize Ref(:AsgMax)
      VPCZoneIdentifier Ref(:Subnets)
      LaunchTemplate({
        LaunchTemplateId: Ref(:LaunchTemplate),
        Version: FnGetAtt(:LaunchTemplate, :LatestVersionNumber)
      })
      Tags ecs_asg_tags.each {|tag| tag[:PropagateAtLaunch]=false}
    }
    
    Output(:AutoScalingGroupName) {
      Value(Ref(:AutoScaleGroup))
      Export FnSub("${EnvironmentName}-#{component_name}-AutoScalingGroupName")
    }
        
    IAM_Role(:DrainECSHookFunctionRole) {
      Path '/'
      AssumeRolePolicyDocument service_assume_role_policy('lambda')
      Policies iam_role_policies(dain_hook_iam_policies)
      Tags ecs_tags
    }
    
    Lambda_Function(:DrainECSHookFunction) {
      Handler 'index.lambda_handler'
      Timeout '300'
      Code({
        ZipFile: <<~LAMBDA
        import boto3, json, os, time

        ecs = boto3.client('ecs')
        autoscaling = boto3.client('autoscaling')

        def lambda_handler(event, context):
            print(json.dumps(event))
            cluster = os.environ['CLUSTER']
            snsTopicArn = event['Records'][0]['Sns']['TopicArn']
            lifecycle_event = json.loads(event['Records'][0]['Sns']['Message'])
            instance_id = lifecycle_event.get('EC2InstanceId')
            if not instance_id:
                print('Got event without EC2InstanceId: %s', json.dumps(event))
                return

            instance_arn = container_instance_arn(cluster, instance_id)
            print('Instance %s has container instance ARN %s' % (lifecycle_event['EC2InstanceId'], instance_arn))

            if not instance_arn:
                return

            while has_tasks(cluster, instance_arn):
                time.sleep(10)

            try:
                print('Terminating instance %s' % instance_id)
                autoscaling.complete_lifecycle_action(
                    LifecycleActionResult='CONTINUE',
                    **pick(lifecycle_event, 'LifecycleHookName', 'LifecycleActionToken', 'AutoScalingGroupName'))
            except Exception as e:
                # Lifecycle action may have already completed.
                print(str(e))


        def container_instance_arn(cluster, instance_id):
            """Turn an instance ID into a container instance ARN."""
            arns = ecs.list_container_instances(cluster=cluster, filter='ec2InstanceId==' + instance_id)['containerInstanceArns']
            if not arns:
                return None
            return arns[0]


        def has_tasks(cluster, instance_arn):
            """Return True if the instance is running tasks for the given cluster."""
            instances = ecs.describe_container_instances(cluster=cluster, containerInstances=[instance_arn])['containerInstances']
            if not instances:
                return False
            instance = instances[0]

            if instance['status'] == 'ACTIVE':
                # Start draining, then try again later
                set_container_instance_to_draining(cluster, instance_arn)
                return True

            tasks = instance['runningTasksCount'] + instance['pendingTasksCount']
            print('Instance %s has %s tasks' % (instance_arn, tasks))

            return tasks > 0


        def set_container_instance_to_draining(cluster, instance_arn):
            ecs.update_container_instances_state(
                cluster=cluster,
                containerInstances=[instance_arn], status='DRAINING')


        def pick(dct, *keys):
            """Pick a subset of a dict."""
            return {k: v for k, v in dct.items() if k in keys}
        LAMBDA
      })
      Role FnGetAtt(:DrainECSHookFunctionRole, :Arn)
      Runtime 'python3.7'
      Environment({
        Variables: {
          CLUSTER: Ref(:EcsCluster)
        }
      })
      Tags ecs_tags
    }
    
    Lambda_Permission(:DrainECSHookPermissions) {
      Action 'lambda:InvokeFunction'
      FunctionName FnGetAtt(:DrainECSHookFunction, :Arn)
      Principal 'sns.amazonaws.com'
      SourceArn Ref(:DrainECSHookTopic)
    }
    
    SNS_Topic(:DrainECSHookTopic) {
      Subscription([
        {
          Endpoint: FnGetAtt(:DrainECSHookFunction, :Arn),
          Protocol: 'lambda'
        }
      ])
      Tags ecs_tags
    }
        
    IAM_Role(:DrainECSHookTopicRole) {
      Path '/'
      AssumeRolePolicyDocument service_assume_role_policy('autoscaling')
      Policies iam_role_policies(dain_hook_topic_iam_policies)
      Tags ecs_tags
    }
    
    AutoScaling_LifecycleHook(:DrainECSHook) {
      AutoScalingGroupName Ref(:AutoScaleGroup)
      LifecycleTransition 'autoscaling:EC2_INSTANCE_TERMINATING'
      DefaultResult 'CONTINUE'
      HeartbeatTimeout '300'
      NotificationTargetARN Ref(:DrainECSHookTopic)
      RoleARN FnGetAtt(:DrainECSHookTopicRole, :Arn)
    }
    
  end
  
end
