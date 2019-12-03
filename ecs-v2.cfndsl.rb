CloudFormation do
  
  ecs_tags = []
  ecs_tags << { Key: 'Name', Value: FnSub("${EnvironmentName}-#{component_name}") }
  ecs_tags << { Key: 'EnvironmentName', Value: Ref(:EnvironmentName) }
  ecs_tags << { Key: 'EnvironmentType', Value: Ref(:EnvironmentType) }
  
  ECS_Cluster(:EcsCluster) {
    ClusterName FnSub(cluster_name) if defined? cluster_name
    ClusterSetting([
        { Name: 'containerInsights', Value: Ref(:ContainerInsights) }
    ])
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
        ZipFile: File.read('lambdas/draining/app.py')
      })
      Role FnGetAtt(:DrainECSHookFunctionRole, :Arn)
      Runtime 'python3.8'
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
      AssumeRolePolicyDocument service_assume_role_policy('lambda')
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
    
    Condition(:ScalingEnabled, FnEquals(Ref(:ScaleEcsInstances), 'true'))
    
    Condition(:ScalingDownEnabled, FnAnd([
      Condition(:ScalingEnabled),
      FnEquals(Ref(:ScaleEcsInstances), 'true')
    ]))
    
    IAM_Role(:EcsScalingFunctionRole) {
      Condition(:ScalingEnabled)
      Path '/'
      AssumeRolePolicyDocument service_assume_role_policy('lambda')
      Policies iam_role_policies(ecs_scaling_iam_policies)
      Tags ecs_tags
    }
    
    Lambda_Function(:EcsScalingFunction) {
      Condition(:ScalingEnabled)
      Handler 'index.lambda_handler'
      Timeout '300'
      Code({
        ZipFile: File.read('lambdas/scaling/app.py')
      })
      Role FnGetAtt(:DrainECSHookFunctionRole, :Arn)
      Runtime 'python3.8'
      Environment({
        Variables: {
          CLUSTER: Ref(:EcsCluster)
        }
      })
      Tags ecs_tags
    }
    
    input = {
      ecs_cluster_name: '${EcsCluster}',
      scalability_index: '${ScalabilityIndex}'
    }
    
    Events_Rule(:EcsScalingEvent) {
      Condition(:ScalingEnabled)
      Description FnSub('Custom scaling meterics for ECS cluster ${EcsCluster}')
      ScheduleExpression 'rate(1 minute)'
      State 'ENABLED'
      Targets([
        {
          Arn: FnGetAtt(:EcsScalingFunction, :Arn),
          Id: FnSub('EcsScalingEvent-${EcsCluster}'),
          Input: FnSub(input.to_json)
        }
      ])
    }
    
    Lambda_Permission(:EcsScalingPermissions) {
      Condition(:ScalingEnabled)
      Action 'lambda:InvokeFunction'
      FunctionName FnGetAtt(:EcsScalingFunction, :Arn)
      Principal 'events.amazonaws.com'
      SourceArn FnGetAtt(:EcsScalingEvent, :Arn)
    }
        
    AutoScaling_ScalingPolicy(:EcsClusterScaleOutPolicy) {
      Condition(:ScalingEnabled)
      AdjustmentType 'ChangeInCapacity'
      AutoScalingGroupName Ref(:AutoScaleGroup)
      Cooldown '120'
      ScalingAdjustment '1'
    }
    
    CloudWatch_Alarm(:EcsClusterScaleOutAlarm) {
      Condition(:ScalingEnabled)
      ActionsEnabled true
      AlarmActions Ref(:EcsClusterScaleOutPolicy)
      ComparisonOperator 'GreaterThanOrEqualToThreshold'
      Dimensions([
        {
          Name: 'ClusterName',
          Value: Ref(:EcsCluster)
        }
      ])
      EvaluationPeriods '1'
      MetricName 'RequiresScaling'
      Namespace 'AWS/ECS'
      Period '60'
      Statistic 'Maximum'
      Threshold '1'
      TreatMissingData 'notBreaching'
      Unit 'None'
    }
    
    AutoScaling_ScalingPolicy(:EcsClusterScaleInPolicy) {
      Condition(:ScalingDownEnabled)
      AdjustmentType 'ChangeInCapacity'
      AutoScalingGroupName Ref(:AutoScaleGroup)
      Cooldown '300'
      ScalingAdjustment '-1'
    }
    
    CloudWatch_Alarm(:EcsClusterScaleInAlarm) {
      Condition(:ScalingDownEnabled)
      ActionsEnabled true
      AlarmActions Ref(:EcsClusterScaleInPolicy)
      ComparisonOperator 'LessThanOrEqualToThreshold'
      Dimensions([
        {
          Name: 'ClusterName',
          Value: Ref(:EcsCluster)
        }
      ])
      EvaluationPeriods '5'
      MetricName 'RequiresScaling'
      Namespace 'AWS/ECS'
      Period '60'
      Statistic 'Maximum'
      Threshold '-1'
      TreatMissingData 'notBreaching'
      Unit 'None'
    }
    
  end
  
end
