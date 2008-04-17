require File.dirname(__FILE__) + '/spec_helper'

describe JsonRpcClient do
  
  before do
    class FooController < ApplicationController
      json_rpc_service :name => 'TestService', :id => 'skdjfhsdhfkjshdjkhskdhfkjshdf'
      json_rpc_procedure :name => 'add', :params => [{:name => 'x', :type => 'any'}, 
                                                     {:name => 'y', :type => 'any'}], 
                         :proc => :+, :idempotent => true
    end
        
    class Foo < JsonRpcClient
      json_rpc_service 'http://localhost:8888/da_service'
    end
        
  end
  
  
  it "should request the system description when first called" do
    Net::HTTP.should_receive(:start).with("localhost", 8888, nil, nil).
              and_return(stringify_symbols_in_hash(FooController.service.system_describe))
    Foo.system_describe.should == {"procs"=>[{"name"=>"add", 
                                              "idempotent"=>true, 
                                              "params"=>[{"name"=>"x", "type"=>"any"}, 
                                                         {"name"=>"y", "type"=>"any"}], 
                                              "return"=>{"type"=>"any"}}], 
                                   "name"=>"TestService", "id"=>"skdjfhsdhfkjshdjkhskdhfkjshdf", "sdversion"=>"1.0"}
  end
  
  
  it "should raise a JsonRpcClient::ServiceError locally when the remote service returns an error" do
    Net::HTTP.should_receive(:start).with("localhost", 8888, nil, nil).
              and_yield(mock_model(Net::HTTP, :request => mock_model(Net::HTTPRequest, 
                                                                     :body => '{"error": {"code": 123, "message": "Disaster!"}}',
                                                                     :content_type => 'application/json')))
    lambda { Foo.add 1, 2 }.should raise_error(JsonRpcClient::ServiceError, 'JSON-RPC error 123: Disaster!')
  end
  
  it "should raise a JsonRpcClient::ServiceDown error when the client cannot reach the remote service" do
    lambda { Foo.add 1, 2 }.should raise_error(JsonRpcClient::ServiceDown)
  end
  
  it "should raise a JsonRpcClient::NotAService when the service does not return JSON" do
    Net::HTTP.should_receive(:start).with("localhost", 8888, nil, nil).
              and_yield(mock_model(Net::HTTP, :request => mock_model(Net::HTTPRequest, 
                                                                     :body => '{"error": {"code": 123, "message": "Disaster!"}}',
                                                                     :content_type => 'text/html')))
    lambda { Foo.add 1, 2 }.should raise_error(JsonRpcClient::NotAService)
  end
  
  it "should raise a JsonRpcClient::ServiceReturnsJunk when the service returns unparseable JSON" do
    Net::HTTP.should_receive(:start).with("localhost", 8888, nil, nil).
              and_yield(mock_model(Net::HTTP, :request => mock_model(Net::HTTPRequest, 
                                                                     :body => '<this>is not<json />but some sort of</markup>',
                                                                     :content_type => 'application/json')))
    lambda { Foo.add 1, 2 }.should raise_error(JsonRpcClient::ServiceReturnsJunk)
  end
  
  it "should yield the exception to a block, if there is one provided" do
    Foo.add(1, 2) { |x| "x is #{x.class}" }.should == "x is JsonRpcClient::ServiceDown"
  end
  
  it "should yield the result to a block, if there is one provided" do
    Net::HTTP.should_receive(:start).with("localhost", 8888, nil, nil).
              and_yield(mock_model(Net::HTTP, :request => mock_model(Net::HTTPRequest, 
                                                                     :body => '{"result": 3}',
                                                                     :content_type => 'application/json')))
    Foo.add(1, 2) { |x| "x is #{x}" }.should == "x is 3"
  end
  
  
end
