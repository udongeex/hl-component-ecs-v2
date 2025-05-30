CfhighlanderTemplate do
  Name 'ecs-v2'
  Description "ecs-v2 - #{component_version}"

  DependsOn 'lib-iam@0.1.0'
  DependsOn 'lib-ec2@0.1.0'

  Parameters do
    ComponentParam 'EnvironmentName', 'dev', isGlobal: true
    
    ComponentParam 'EnvironmentType', 'development', 
        allowedValues: ['development','production'], isGlobal: true
    
    ComponentParam 'VPCId', type: 'AWS::EC2::VPC::Id'
    
    ComponentParam 'ContainerInsights', 'disabled', 
        allowedValues: ['enabled','disabled']
    
    unless fargate_only_cluster
      
      ComponentParam 'KeyPair'
      
      ComponentParam 'Ami', '/aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id', 
          type: 'AWS::SSM::Parameter::Value<AWS::EC2::Image::Id>'
      
      ComponentParam 'InstanceType', 't3.small'
      
      ComponentParam 'Spot', 'false', 
          allowedValues: ['true','false']
      
      ComponentParam 'Subnets', type: 'CommaDelimitedList'
      
      ComponentParam 'AsgDesired', '1'
      ComponentParam 'AsgMin', '1'
      ComponentParam 'AsgMax', '2'  

      ComponentParam 'EnableScaling', 'false', allowedValues: ['true','false']
      ComponentParam 'EnableTargetTrackingScaling', 'false', allowedValues: ['true','false']
      ComponentParam 'volumes', '[]',
        description: 'CloudFormation BlockDeviceMappings to attach extra EBS disks'
    end
    
  end

end
