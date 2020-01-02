require 'yaml'

describe 'compiled component' do
  
  context 'cftest' do
    it 'compiles test' do
      expect(system("cfhighlander cftest #{@validate} --tests tests/default.test.yaml")).to be_truthy
    end      
  end
  
  let(:template) { YAML.load_file("#{File.dirname(__FILE__)}/../out/tests/default/ecs-v2.compiled.yaml") }

  context 'Resource EcsCluster' do

    let(:properties) { template["Resources"]["EcsCluster"]["Properties"] }

    it 'has property ClusterSettings' do
      expect(properties["ClusterSettings"]).to eq([{"Name"=>"containerInsights", "Value"=>{"Ref"=>"ContainerInsights"}}])
    end

    it 'has property Tags' do
      expect(properties["Tags"]).to eq([
        {"Key"=>"Name", "Value"=>{"Fn::Sub"=>"${EnvironmentName}-ecs-v2"}}, 
        {"Key"=>"EnvironmentName", "Value"=>{"Ref"=>"EnvironmentName"}}, 
        {"Key"=>"EnvironmentType", "Value"=>{"Ref"=>"EnvironmentType"}}])
    end

  end

  context 'Resource SecurityGroupEcs' do

    let(:properties) { template["Resources"]["SecurityGroupEcs"]["Properties"] }

    it 'has property VpcId' do
      expect(properties["VpcId"]).to eq({"Ref"=>"VPCId"})
    end

    it 'has property GroupDescription' do
      expect(properties["GroupDescription"]).to eq({"Fn::Sub"=>"${EnvironmentName}-ecs-v2"})
    end


    it 'has property Tags' do
      expect(properties["Tags"]).to eq([
        {"Key"=>"Name", "Value"=>{"Fn::Sub"=>"${EnvironmentName}-ecs-v2"}}, 
        {"Key"=>"EnvironmentName", "Value"=>{"Ref"=>"EnvironmentName"}}, 
        {"Key"=>"EnvironmentType", "Value"=>{"Ref"=>"EnvironmentType"}}])
    end

  end

  context 'Resource Role' do

    let(:properties) { template["Resources"]["Role"]["Properties"] }

    it 'has property Path' do
      expect(properties["Path"]).to eq("/")
    end

    it 'has property AssumeRolePolicyDocument' do
      expect(properties["AssumeRolePolicyDocument"]).to eq({"Version"=>"2012-10-17", "Statement"=>[{"Effect"=>"Allow", "Principal"=>{"Service"=>"ec2.amazonaws.com"}, "Action"=>"sts:AssumeRole"}]})
    end

    it 'has property Policies' do
      expect(properties["Policies"]).to eq([{"PolicyName"=>"ecs-container-instance", "PolicyDocument"=>{"Statement"=>[{"Sid"=>"ecscontainerinstance", "Action"=>["ecs:CreateCluster", "ecs:DeregisterContainerInstance", "ecs:DiscoverPollEndpoint", "ecs:Poll", "ecs:RegisterContainerInstance", "ecs:StartTelemetrySession", "ecs:Submit*", "ecr:GetAuthorizationToken", "ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage", "logs:CreateLogStream", "logs:PutLogEvents"], "Resource"=>["*"], "Effect"=>"Allow"}]}}, {"PolicyName"=>"ecs-service-scheduler", "PolicyDocument"=>{"Statement"=>[{"Sid"=>"ecsservicescheduler", "Action"=>["ec2:AuthorizeSecurityGroupIngress", "ec2:Describe*", "elasticloadbalancing:DeregisterInstancesFromLoadBalancer", "elasticloadbalancing:DeregisterTargets", "elasticloadbalancing:Describe*", "elasticloadbalancing:RegisterInstancesWithLoadBalancer", "elasticloadbalancing:RegisterTargets"], "Resource"=>["*"], "Effect"=>"Allow"}]}}])
    end

    it 'has property Tags' do
      expect(properties["Tags"]).to eq([
        {"Key"=>"Name", "Value"=>{"Fn::Sub"=>"${EnvironmentName}-ecs-v2"}}, 
        {"Key"=>"EnvironmentName", "Value"=>{"Ref"=>"EnvironmentName"}}, 
        {"Key"=>"EnvironmentType", "Value"=>{"Ref"=>"EnvironmentType"}}])
    end

  end

  context 'Resource InstanceProfile' do

    let(:properties) { template["Resources"]["InstanceProfile"]["Properties"] }

    it 'has property Path' do
      expect(properties["Path"]).to eq("/")
    end

    it 'has property Roles' do
      expect(properties["Roles"]).to eq([{"Ref"=>"Role"}])
    end

  end

  context 'Resource LaunchTemplate' do

    let(:properties) { template["Resources"]["LaunchTemplate"]["Properties"] }
    let(:userdata) { properties["LaunchTemplateData"]["UserData"]["Fn::Base64"]["Fn::Sub"] }

    it 'has property LaunchTemplateData' do
      expect(properties["LaunchTemplateData"]).to be_kind_of(Hash)
    end

  end

  context 'Resource AutoScaleGroup' do

    let(:properties) { template["Resources"]["AutoScaleGroup"]["Properties"] }

    it 'has property DesiredCapacity' do
      expect(properties["DesiredCapacity"]).to eq({"Ref"=>"AsgDesired"})
    end

    it 'has property MinSize' do
      expect(properties["MinSize"]).to eq({"Ref"=>"AsgMin"})
    end

    it 'has property MaxSize' do
      expect(properties["MaxSize"]).to eq({"Ref"=>"AsgMax"})
    end

    it 'has property VPCZoneIdentifier' do
      expect(properties["VPCZoneIdentifier"]).to eq({"Ref"=>"Subnets"})
    end

    it 'has property LaunchTemplate' do
      expect(properties["LaunchTemplate"]).to eq({"LaunchTemplateId"=>{"Ref"=>"LaunchTemplate"}, "Version"=>{"Fn::GetAtt"=>["LaunchTemplate", "LatestVersionNumber"]}})
    end

    it 'has property Tags' do
      expect(properties["Tags"]).to eq([
        {"Key"=>"Name", "Value"=>{"Fn::Sub"=>"${EnvironmentName}-ecs-v2"}, "PropagateAtLaunch"=>false}, 
        {"Key"=>"EnvironmentName", "Value"=>{"Ref"=>"EnvironmentName"}, "PropagateAtLaunch"=>false}, 
        {"Key"=>"EnvironmentType", "Value"=>{"Ref"=>"EnvironmentType"}, "PropagateAtLaunch"=>false}])
    end

  end

  context 'Resource DrainECSHookFunctionRole' do

    let(:properties) { template["Resources"]["DrainECSHookFunctionRole"]["Properties"] }

    it 'has property Path' do
      expect(properties["Path"]).to eq("/")
    end

    it 'has property AssumeRolePolicyDocument' do
      expect(properties["AssumeRolePolicyDocument"]).to eq({"Version"=>"2012-10-17", "Statement"=>[{"Effect"=>"Allow", "Principal"=>{"Service"=>"lambda.amazonaws.com"}, "Action"=>"sts:AssumeRole"}]})
    end

    it 'has property Policies' do
      expect(properties["Policies"]).to eq([{"PolicyName"=>"ec2", "PolicyDocument"=>{"Statement"=>[{"Sid"=>"ec2", "Action"=>["ec2:DescribeInstances", "ec2:DescribeInstanceAttribute", "ec2:DescribeInstanceStatus", "ec2:DescribeHosts"], "Resource"=>["*"], "Effect"=>"Allow"}]}}, {"PolicyName"=>"autoscaling", "PolicyDocument"=>{"Statement"=>[{"Sid"=>"autoscaling", "Action"=>["autoscaling:CompleteLifecycleAction"], "Resource"=>[{"Fn::Sub"=>"aws:aws:autoscaling:${AWS::Region}:${AWS::AccountId}:autoScalingGroup:*:autoScalingGroupName/${AutoScaleGroup}"}], "Effect"=>"Allow"}]}}, {"PolicyName"=>"ecs1", "PolicyDocument"=>{"Statement"=>[{"Sid"=>"ecs1", "Action"=>["ecs:DescribeContainerInstances", "ecs:DescribeTasks"], "Resource"=>["*"], "Effect"=>"Allow"}]}}, {"PolicyName"=>"ecs2", "PolicyDocument"=>{"Statement"=>[{"Sid"=>"ecs2", "Action"=>["ecs:ListContainerInstances", "ecs:SubmitContainerStateChange", "ecs:SubmitTaskStateChange"], "Resource"=>[{"Fn::GetAtt"=>["EcsCluster", "Arn"]}], "Effect"=>"Allow"}]}}, {"PolicyName"=>"ecs3", "PolicyDocument"=>{"Statement"=>[{"Sid"=>"ecs3", "Action"=>["ecs:UpdateContainerInstancesState", "ecs:ListTasks"], "Resource"=>["*"], "Effect"=>"Allow", "Condition"=>{"ArnEquals"=>{"ecs:cluster"=>{"Fn::GetAtt"=>["EcsCluster", "Arn"]}}}}]}}])
    end

    it 'has property Tags' do
      expect(properties["Tags"]).to eq([{"Key"=>"Name", "Value"=>{"Fn::Sub"=>"${EnvironmentName}-ecs-v2"}}, {"Key"=>"EnvironmentName", "Value"=>{"Ref"=>"EnvironmentName"}}, {"Key"=>"EnvironmentType", "Value"=>{"Ref"=>"EnvironmentType"}}])
    end

  end

  context 'Resource DrainECSHookFunction' do

    let(:properties) { template["Resources"]["DrainECSHookFunction"]["Properties"] }

    it 'has property Handler' do
      expect(properties["Handler"]).to eq("index.lambda_handler")
    end

    it 'has property Timeout' do
      expect(properties["Timeout"]).to eq(300)
    end

    it 'has property Code' do
      expect(properties["Code"]).to include("ZipFile" => a_kind_of(String))
    end

    it 'has property Role' do
      expect(properties["Role"]).to eq({"Fn::GetAtt"=>["DrainECSHookFunctionRole", "Arn"]})
    end

    it 'has property Runtime' do
      expect(properties["Runtime"]).to eq("python3.7")
    end

    it 'has property Environment' do
      expect(properties["Environment"]).to eq({"Variables"=>{"CLUSTER"=>{"Ref"=>"EcsCluster"}}})
    end

    it 'has property Tags' do
      expect(properties["Tags"]).to eq([
        {"Key"=>"Name", "Value"=>{"Fn::Sub"=>"${EnvironmentName}-ecs-v2"}}, 
        {"Key"=>"EnvironmentName", "Value"=>{"Ref"=>"EnvironmentName"}}, 
        {"Key"=>"EnvironmentType", "Value"=>{"Ref"=>"EnvironmentType"}}])
    end

  end

  context 'Resource DrainECSHookPermissions' do

    let(:properties) { template["Resources"]["DrainECSHookPermissions"]["Properties"] }

    it 'has property Action' do
      expect(properties["Action"]).to eq("lambda:InvokeFunction")
    end

    it 'has property FunctionName' do
      expect(properties["FunctionName"]).to eq({"Fn::GetAtt"=>["DrainECSHookFunction", "Arn"]})
    end

    it 'has property Principal' do
      expect(properties["Principal"]).to eq("sns.amazonaws.com")
    end

    it 'has property SourceArn' do
      expect(properties["SourceArn"]).to eq({"Ref"=>"DrainECSHookTopic"})
    end

  end

  context 'Resource DrainECSHookTopic' do

    let(:properties) { template["Resources"]["DrainECSHookTopic"]["Properties"] }

    it 'has property Subscription' do
      expect(properties["Subscription"]).to eq([{"Endpoint"=>{"Fn::GetAtt"=>["DrainECSHookFunction", "Arn"]}, "Protocol"=>"lambda"}])
    end

    it 'has property Tags' do
      expect(properties["Tags"]).to eq([
        {"Key"=>"Name", "Value"=>{"Fn::Sub"=>"${EnvironmentName}-ecs-v2"}}, 
        {"Key"=>"EnvironmentName", "Value"=>{"Ref"=>"EnvironmentName"}}, 
        {"Key"=>"EnvironmentType", "Value"=>{"Ref"=>"EnvironmentType"}}])
    end

  end

  context 'Resource DrainECSHookTopicRole' do

    let(:properties) { template["Resources"]["DrainECSHookTopicRole"]["Properties"] }

    it 'has property Path' do
      expect(properties["Path"]).to eq("/")
    end

    it 'has property AssumeRolePolicyDocument' do
      expect(properties["AssumeRolePolicyDocument"]).to eq({"Version"=>"2012-10-17", "Statement"=>[{"Effect"=>"Allow", "Principal"=>{"Service"=>"autoscaling.amazonaws.com"}, "Action"=>"sts:AssumeRole"}]})
    end

    it 'has property Policies' do
      expect(properties["Policies"]).to eq([{"PolicyName"=>"sns", "PolicyDocument"=>{"Statement"=>[{"Sid"=>"sns", "Action"=>["sns:Publish"], "Resource"=>[{"Ref"=>"DrainECSHookTopic"}], "Effect"=>"Allow"}]}}])
    end

    it 'has property Tags' do
      expect(properties["Tags"]).to eq([
        {"Key"=>"Name", "Value"=>{"Fn::Sub"=>"${EnvironmentName}-ecs-v2"}}, 
        {"Key"=>"EnvironmentName", "Value"=>{"Ref"=>"EnvironmentName"}}, 
        {"Key"=>"EnvironmentType", "Value"=>{"Ref"=>"EnvironmentType"}}])
    end

  end

  context 'Resource DrainECSHook' do

    let(:properties) { template["Resources"]["DrainECSHook"]["Properties"] }

    it 'has property AutoScalingGroupName' do
      expect(properties["AutoScalingGroupName"]).to eq({"Ref"=>"AutoScaleGroup"})
    end

    it 'has property LifecycleTransition' do
      expect(properties["LifecycleTransition"]).to eq("autoscaling:EC2_INSTANCE_TERMINATING")
    end

    it 'has property DefaultResult' do
      expect(properties["DefaultResult"]).to eq("CONTINUE")
    end

    it 'has property HeartbeatTimeout' do
      expect(properties["HeartbeatTimeout"]).to eq(300)
    end

    it 'has property NotificationTargetARN' do
      expect(properties["NotificationTargetARN"]).to eq({"Ref"=>"DrainECSHookTopic"})
    end

    it 'has property RoleARN' do
      expect(properties["RoleARN"]).to eq({"Fn::GetAtt"=>["DrainECSHookTopicRole", "Arn"]})
    end

  end
  
  context 'Parameters' do
    
    let(:parameters) { template["Parameters"].keys }
    
    it 'has parameter EnvironmentName' do
      expect(parameters).to include('EnvironmentName')
    end
    
    it 'has parameter EnvironmentType' do
      expect(parameters).to include('EnvironmentType')
    end
    
    it 'has parameter VPCId' do
      expect(parameters).to include('VPCId')
    end
    
    it 'has type set' do
      expect(template["Parameters"]["VPCId"]["Type"]).to eq('AWS::EC2::VPC::Id')
    end
    
    it 'has parameter ContainerInsights' do
      expect(parameters).to include('ContainerInsights')
    end
    
    it 'has allowed values' do
      expect(template["Parameters"]["ContainerInsights"]["AllowedValues"]).to eq(['enabled','disabled'])
    end
    
    it 'has parameter KeyPair' do
      expect(parameters).to include('KeyPair')
    end
    
    it 'has parameter Ami' do
      expect(parameters).to include('Ami')
    end
    
    it 'has type set' do
      expect(template["Parameters"]["Ami"]["Type"]).to eq('AWS::SSM::Parameter::Value<AWS::EC2::Image::Id>')
    end
    
    it 'has default value' do
      expect(template["Parameters"]["Ami"]["Default"]).to eq('/aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id')
    end
    
    it 'has parameter InstanceType' do
      expect(parameters).to include('InstanceType')
    end
    
    it 'has parameter Spot' do
      expect(parameters).to include('Spot')
    end
    
    it 'has allowed values' do
      expect(template["Parameters"]["Spot"]["AllowedValues"]).to eq(['true','false'])
    end
    
    it 'has parameter Subnets' do
      expect(parameters).to include('Subnets')
    end
    
    it 'has parameter AsgDesired' do
      expect(parameters).to include('AsgDesired')
    end
    
    it 'has parameter AsgMin' do
      expect(parameters).to include('AsgMin')
    end
    
    it 'has parameter AsgMax' do
      expect(parameters).to include('AsgMax')
    end
    
  end

end
