require File.dirname(__FILE__) + '/spec_helper'


describe JsonRpcService do
  
  describe "controller GET calls" do
  
    before do
      class FooController < ApplicationController
        json_rpc_service :name => 'TestService', :id => 'skdjfhsdhfkjshdjkhskdhfkjshdf'
        json_rpc_procedure :name => 'add', :params => [{:name => 'x', :type => 'any'}, 
                                                       {:name => 'y', :type => 'any'}], 
                           :proc => :+, :idempotent => true
        
      end
      @request = ActionController::TestRequest.new
      @request.env['HTTP_USER_AGENT'] = 'Internet Exploder 12.0 - still not compliant AND PROUD OF IT'
      @request.env['HTTP_ACCEPT'] = 'application/json'
      @request.env['QUERY_STRING'] = 'x=12&y=23'
    end
  
    it "should require a User Agent header" do
      @request.env['HTTP_USER_AGENT'] = nil
      req = FooController.service.process @request, {:method => ['add']}
      req.status_code.should == 500
      req.response.should == "{\"version\": \"1.1\", \"error\": {\"code\":999,\"name\":\"JSONRPCError\",\"message\":\"User-Agent header not specified\"}}\n"
    end
  
    it "should require a HTTP Accept header specifying JSON" do
      @request.env['HTTP_ACCEPT'] = 'application/text'
      req = FooController.service.process @request, {:method => ['add']}
      req.status_code.should == 500
      req.response.should == "{\"version\": \"1.1\", \"error\": {\"code\":999,\"name\":\"JSONRPCError\",\"message\":\"Accept header must be application\\/json\"}}\n"
    end
    
    it "should be able to add two strings" do
      req = FooController.service.process @request, {:method => ['add']}
      req.status_code.should be_nil
      req.response.should == "{\"version\": \"1.1\", \"result\": \"1223\"}\n"
    end

    it "should aggregate multiple occurrences of the same arg name" do
      @request.env['QUERY_STRING'] = 'x=AAA&y=BBB&y=CCCCCC&x=DDDDDD'
      req = FooController.service.process @request, {:method => ['add']}
      req.status_code.should be_nil
      req.response.should == "{\"version\": \"1.1\", \"result\": [\"AAA\",\"DDDDDD\",\"BBB\",\"CCCCCC\"]}\n"
    end

    it "should handle named args" do
      @request.env['QUERY_STRING'] = 'y=223&x=1'
      req = FooController.service.process @request, {:method => ['add']}
      req.status_code.should be_nil
      req.response.should == "{\"version\": \"1.1\", \"result\": \"1223\"}\n"
    end
    
    it "should also be callable using POST" do
      @request.env['HTTP_ACCEPT'] = 'application/json'
      @request.env['REQUEST_METHOD'] = 'POST'
      @request.env['CONTENT_TYPE'] = 'application/json'
      @request.env['RAW_POST_DATA'] = '{"version": "1.1", "method": "add", "params": ["100", "33"]}'
      req = FooController.service.process @request, {:method => ['add']}
      req.status_code.should be_nil
      req.response.should == "{\"version\": \"1.1\", \"result\": \"10033\"}\n"
    end

  end


  describe "controller POST calls" do
  
    before do
      class FooController < ApplicationController
        json_rpc_service :name => 'TestService', :id => 'skdjfhsdhfkjshdjkhskdhfkjshdf'
        json_rpc_procedure :name => 'sub', :params => [{:name => 'x', :type => 'num'}, 
                                                       {:name => 'y', :type => 'num'}], 
                           :proc => :-
      end
      @request = ActionController::TestRequest.new
      @request.env['HTTP_USER_AGENT'] = 'Internet Exploder 12.0 - still not compliant AND PROUD OF IT'
      @request.env['HTTP_ACCEPT'] = 'application/json'
      @request.env['REQUEST_METHOD'] = 'POST'
      @request.env['CONTENT_TYPE'] = 'application/json'
      @request.env['RAW_POST_DATA'] = '{"version": "1.1", "method": "sub", "params": [100, 33]}'
    end
    
    it "should not be callable via GET" do
      @request.env['REQUEST_METHOD'] = 'GET'
      @request.env['RAW_POST_DATA'] = nil
      @request.env['QUERY_STRING'] = 'x=12&y=23'
      req = FooController.service.process @request, {:method => ['sub']}
      req.status_code.should == 500
      req.response.should == "{\"version\": \"1.1\", \"error\": {\"code\":999,\"name\":\"JSONRPCError\",\"message\":\"This method is not idempotent and can only be called using POST.\"}}\n"
    end
  
    it "should require POST data specifying a version" do
      @request.env['RAW_POST_DATA'] = '{"method": "add", "params": [10, 25]}'
      req = FooController.service.process @request, {:method => ['sub']}
      req.status_code.should == 500
      req.response.should == "{\"version\": \"1.1\", \"error\": {\"code\":999,\"name\":\"JSONRPCError\",\"message\":\"JSON-RPC client protocol version must be specified in POSTs\"}}\n"
    end

    it "should handle positional arguments" do
      req = FooController.service.process @request, {:method => ['sub']}
      req.status_code.should be_nil
      req.response.should == "{\"version\": \"1.1\", \"result\": 67}\n"
    end
    
    it "should handle named arguments" do
      @request.env['RAW_POST_DATA'] = '{"version": "2.99", "method": "sub", "params": {"y": 33, "x": 100}}'
      req = FooController.service.process @request, {:method => ['sub']}
      req.status_code.should be_nil
      req.response.should == "{\"version\": \"1.1\", \"result\": 67}\n"
    end

    it "should handle arguments with numerical order" do
      @request.env['RAW_POST_DATA'] = '{"version": "2.99", "method": "sub", "params": {"1": 33, "0": 100}}'
      req = FooController.service.process @request, {:method => ['sub']}
      req.status_code.should be_nil
      req.response.should == "{\"version\": \"1.1\", \"result\": 67}\n"
    end

    it "should handle mixed arguments" do
      @request.env['RAW_POST_DATA'] = '{"version": "2.99", "method": "sub", "params": {"y": 33, "0": 100}}'
      req = FooController.service.process @request, {:method => ['sub']}
      req.status_code.should be_nil
      req.response.should == "{\"version\": \"1.1\", \"result\": 67}\n"
    end

    it "should require a Content-Type header specifying JSON" do
      @request.env['CONTENT_TYPE'] = 'application/html'
      req = FooController.service.process @request, {:method => ['sub']}
      req.status_code.should == 500
      req.response.should == "{\"version\": \"1.1\", \"error\": {\"code\":999,\"name\":\"JSONRPCError\",\"message\":\"Content-Type header must be application\\/json\"}}\n"
    end

    it "should require POST data specifying the method to call" do
      @request.env['RAW_POST_DATA'] = '{"version": "2.99", "params": [10, 25]}'
      req = FooController.service.process @request, {:method => ['sub']}
      req.status_code.should == 500
      req.response.should == "{\"version\": \"1.1\", \"error\": {\"code\":999,\"name\":\"JSONRPCError\",\"message\":\"Method not specified\"}}\n"
    end

    it "should require POST data specifying an existing method to call" do
      @request.env['RAW_POST_DATA'] = '{"version": "2.99", "method": "zzz", "params": [10, 25]}'
      req = FooController.service.process @request, {:method => ['sub']}
      req.status_code.should == 500
      req.response.should == "{\"version\": \"1.1\", \"error\": {\"code\":999,\"name\":\"JSONRPCError\",\"message\":\"This JSON-RPC service does not provide a 'zzz' method.\"}}\n"
    end
    
    it "should barf on missing numerical arguments" do
      @request.env['RAW_POST_DATA'] = '{"version": "2.99", "method": "sub", "params": [10]}'
      req = FooController.service.process @request, {:method => ['sub']}
      req.status_code.should == 500
      req.response.should == "{\"version\": \"1.1\", \"error\": {\"code\":999,\"name\":\"JSONRPCError\",\"message\":\"The arg y must be numeric (was null)\"}}\n"
    end

    it "should barf on excess arguments" do
      @request.env['RAW_POST_DATA'] = '{"version": "2.99", "method": "sub", "params": [10, 20, 30, 40]}'
      req = FooController.service.process @request, {:method => ['sub']}
      req.status_code.should == 500
    end

    it "should barf on arguments of the wrong type" do
      @request.env['RAW_POST_DATA'] = '{"version": "2.99", "method": "sub", "params": {"y": 10, "x": "blah"}}'
      req = FooController.service.process @request, {:method => ['sub']}
      req.status_code.should == 500
      req.response.should == "{\"version\": \"1.1\", \"error\": {\"code\":999,\"name\":\"JSONRPCError\",\"message\":\"The arg x must be numeric (was \\\"blah\\\")\"}}\n"
    end

  end


  describe "controller calls other than GET and POST" do
  
    before do
      class FooController < ApplicationController
        json_rpc_service :name => 'TestService', :id => 'skdjfhsdhfkjshdjkhskdhfkjshdf'
        json_rpc_procedure :name => 'add', :params => [{:name => 'x', :type => 'any'}, 
                                                       {:name => 'y', :type => 'any'}], 
                           :proc => :+, :idempotent => true
        
      end
      @request = ActionController::TestRequest.new
      @request.env['HTTP_USER_AGENT'] = 'Internet Exploder 12.0 - still not compliant AND PROUD OF IT'
      @request.env['HTTP_ACCEPT'] = 'application/json'
      @request.env['QUERY_STRING'] = 'x=12&y=23'
    end
  
    it "should not be possible" do
      @request.env['REQUEST_METHOD'] = 'PUT'
      req = FooController.service.process @request, {:method => ['add']}
      req.status_code.should == 500
      req.response.should == "{\"version\": \"1.1\", \"error\": {\"code\":999,\"name\":\"JSONRPCError\",\"message\":\"Only POST and GET supported\"}}\n"
    end
    
  end  

end