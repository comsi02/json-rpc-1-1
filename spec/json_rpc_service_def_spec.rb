require File.dirname(__FILE__) + '/spec_helper'

describe JsonRpcService do
  
  
  describe "the json_rpc_service declaration" do
    
    def valid_args
      { :name => 'TestService', :id => 'skdjfhsdhfkjshdjkhskdhfkjshdf' }
    end
    
    before do
      class Foo < ActionController::Base; end
    end
    
    it "should populate the service variable" do
      Foo.json_rpc_service valid_args
      Foo.service.should be_an_instance_of(JsonRpcService::Service)
    end
    
    it "should require a service name" do
      lambda { Foo.json_rpc_service(valid_args.except(:name)) }.should raise_error(JsonRpcService::Service::Error, 
                                                                                   'JSON-RPC service must have a :name')
    end
    
    it "should require a service id" do
      lambda { Foo.json_rpc_service(valid_args.except(:id)) }.should raise_error(JsonRpcService::Service::Error, 
                                                                                 'JSON-RPC service must have an :id')
    end
    
    it "should not accept a :sdversion other than 1.0" do
      lambda { Foo.json_rpc_service(valid_args.with(:sdversion => '1.1')) }.
        should raise_error(JsonRpcService::Service::Error, 'JSON-RPC service must have an :sdversion of 1.0')
    end
    
    it "should make a service description accessible" do
      Foo.json_rpc_service valid_args
      sd = Foo.service.system_describe
      sd.should be_an_instance_of(Hash)  
      sd[:name].should == 'TestService'
      sd[:id].should == 'skdjfhsdhfkjshdjkhskdhfkjshdf'
      sd[:sdversion].should == '1.0'
    end
    
    it "should define no procs initially" do
      Foo.json_rpc_service valid_args
      Foo.service.system_describe[:procs].should == []
    end
  
  end
  
  
  describe "the json_rpc_procedure declaration" do
        
    def valid_args
      { :name => 'test', :proc => lambda { |x, y| x + y } }
    end

    before do
      class Foo < ActionController::Base
        Foo.json_rpc_service :name => 'TestService', :id => 'skdjfhsdhfkjshdjkhskdhfkjshdf'
      end
    end
    
    it "should take a minimum number of args" do
      Foo.json_rpc_procedure valid_args
    end
    
    it "should require a name" do
      lambda { Foo.json_rpc_procedure valid_args.except(:name)}.should raise_error(JsonRpcService::Service::Error, 
                                                                                   'JSON-RPC procedure must have a name')
    end
    
    it "should require a proc" do
      lambda { Foo.json_rpc_procedure valid_args.except(:proc)}.should raise_error(JsonRpcService::Service::Error, 
                                                                                   'JSON-RPC procedure must specify a :proc to be executed locally')
    end
    
    it "should convert a symbol proc to a real proc" do
      Foo.json_rpc_procedure valid_args.with(:proc => :+)
      Foo.service.procs['test'][:proc].should be_an_instance_of(Proc)
    end
    
    it "should update the system_describe info with default data" do
      Foo.json_rpc_procedure valid_args
      Foo.service.system_describe[:procs].should == [{:params=>[], :name=>"test", :return=>{:type=>"any"}}]
    end
    
    it "should accept untyped argument specifications" do
      Foo.json_rpc_procedure valid_args.with(:params => ['bar', {:name => 'baz'}, 'foobar'])
      Foo.service.system_describe[:procs].should == [{:return=>{:type=>"any"}, :name=>"test", 
                                                      :params=>[{:type=>"any", :name=>"bar"}, 
                                                                {:type=>"any", :name=>"baz"}, 
                                                                {:type=>"any", :name=>"foobar"}]}]
    end
    
    it "should accept typed argument specifications" do
      Foo.json_rpc_procedure valid_args.with(:params => [{:name => 'bar', :type => 'num'}, {:name => 'baz', :type => 'str'}, {:name => 'foobar', :type => 'bit'}])
      Foo.service.system_describe[:procs].should == [{:return=>{:type=>"any"}, :name=>"test", 
                                                      :params=>[{:type=>"num", :name=>"bar"}, 
                                                                {:type=>"str", :name=>"baz"}, 
                                                                {:type=>"bit", :name=>"foobar"}]}]
    end
    
    it "should accept a return type specification" do
      Foo.json_rpc_procedure valid_args.with(:return => {:type => 'obj'})
      Foo.service.system_describe[:procs].should == [{:return=>{:type=>"obj"}, :name=>"test", :params=>[]}]
    end
    
    it "should accept idempotency declarations" do
      Foo.json_rpc_procedure valid_args.with(:idempotent => true)
      Foo.service.procs['test'][:idempotent].should be_true
    end
     
  end
  
end
