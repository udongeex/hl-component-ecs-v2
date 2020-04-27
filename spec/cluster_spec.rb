require 'yaml'

describe 'compiled component' do
  
  context 'cftest' do
    it 'compiles test' do
      expect(system("cfhighlander cftest #{@validate} --tests tests/cluster.test.yaml")).to be_truthy
    end      
  end
  
  let(:template) { YAML.load_file("#{File.dirname(__FILE__)}/../out/tests/cluster/ecs-v2.compiled.yaml") }

  context 'Resource EcsCluster' do

    let(:properties) { template["Resources"]["EcsCluster"]["Properties"] }

    it 'has property ClusterName' do
      expect(properties["ClusterName"]).to eq({"Fn::Sub"=>"${EnvironmentName}-MyCluster"})
    end

  end

  context 'Resource SecurityGroupEcs' do

    let(:properties) { template["Resources"]["SecurityGroupEcs"]["Properties"] }

    it 'has property SecurityGroupIngress' do
      expect(properties["SecurityGroupIngress"]).to eq([{"FromPort"=>8080, "IpProtocol"=>"TCP", "ToPort"=>8080, "Description"=>{"Fn::Sub"=>"allow access from localhost to app"}, "CidrIp"=>{"Fn::Sub"=>"10.0.0.0/16"}}])
    end

  end

  context 'Resource LaunchTemplate' do

    let(:properties) { template["Resources"]["LaunchTemplate"]["Properties"] }
    let(:userdata) { properties["LaunchTemplateData"]["UserData"]["Fn::Base64"]["Fn::Sub"] }
    
    it 'includes ecs_agent_config in the userdata' do
      expect(userdata).to include("echo ECS_AWSVPC_BLOCK_IMDS=true >> /etc/ecs/ecs.config")
      expect(userdata).to include("echo ECS_ENABLE_SPOT_INSTANCE_DRAINING=true >> /etc/ecs/ecs.config")
      expect(userdata).to include("echo ECS_ENGINE_TASK_CLEANUP_WAIT_DURATION=10m >> /etc/ecs/ecs.config")
    end
    
    it 'includes custom userdata config in the userdata' do
      expect(userdata).to include("\nmkdir -p /opt/test")
      expect(userdata).to include("\necho \"done!\"")
    end

  end

end
