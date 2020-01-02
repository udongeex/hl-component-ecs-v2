require 'yaml'

describe 'compiled component' do
  
  context 'cftest' do
    it 'compiles test' do
      expect(system("cfhighlander cftest #{@validate} --tests tests/fargate.test.yaml")).to be_truthy
    end      
  end
  
  let(:template) { YAML.load_file("#{File.dirname(__FILE__)}/../out/tests/fargate/ecs-v2.compiled.yaml") }
  
  context 'Resources' do
    
    let(:types) { template["Resources"].collect { |key,value| value["Type"] } }
    
    it 'only contains' do
      expect(types).to eq(['AWS::ECS::Cluster'])
    end
    
  end
  
  context 'Parameters' do
    
    let(:parameters) { template["Parameters"].keys }
    
    it 'only contains' do
      expect(parameters).to eq(['EnvironmentName', 'EnvironmentType', 'VPCId', 'ContainerInsights'])
    end
    
  end

end
