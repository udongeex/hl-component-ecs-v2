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
    
    Condition(:SpotEnabled, FnNot(FnEquals(Ref(:Spot), 'true')))
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
      UpdatePolicy(:AutoScalingRollingUpdate, {
        MaxBatchSize: Ref(:MaxBatchSize),
        MinInstancesInService: Ref(:MinInstancesInService),
        SuspendProcesses: %w(HealthCheck ReplaceUnhealthy AZRebalance AlarmNotification ScheduledActions)
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
    
  end
  
end
