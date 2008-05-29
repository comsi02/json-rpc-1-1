#
# This is the JSON-RPC Service.
#
module JsonRpcService
      
  require 'json'
      
  def self.included(base)
    base.extend ClassMethods
  end
  
  
  module ClassMethods
    #
    # Declare that this controller is a JSON-RPC service. See the Server#initialize
    # method for valid options.
    #
    def json_rpc_service(opts={})
      session :off
      include JsonRpcService::InstanceMethods
      @service = Service.new opts
    end
    
    #
    # Declares a callable API method for this service. See the README for valid
    # options.
    #
    def json_rpc_procedure(opts={})
      @service.add_procedure opts
    end
    
    #
    # Turns off the service, making it return HTTP 503 as a status code.
    #
    def disable
      @service.disabled = true
    end
    
    #
    # Turns on the service, making it accept API calls as usual.
    #
    def enable
      @service.disabled = false
    end
    
    private
      #
      # Returns the service object for this class.
      #
      def service
        @service
      end
  end
  
  
  module InstanceMethods
    #
    # This method is the action which should be called for all incoming API calls.
    # Use the config/routes.rb to direct all calls for the service to this method.
    # It will be automatically included in the controller class.
    #
    def receive_json_rpc_request
      service = self.class.service
      render(:text => 'JSON-RPC server disabled', :status => 503) and return if service.disabled
      req = service.process request, params
      headers['Content-Type'] = 'application/json'
      render :text => req.response, :status => req.status_code
    end
  end
  

  #
  # This class defines the server side of the JSON-RPC protocol handler.
  # There may exist any number of services on each server. All each service
  # needs is a route of its own (in Rails). Each request is processed in
  # the context of one particular Service.
  #
  class Service
        
    class Error < RuntimeError; end

    attr_reader :procs
    attr :disabled
        
    # 
    # Sets up a new service. Raises exceptions if the service description is
    # incorrect or incomplete. The :id must be a valid UUID according to the JSON-RPC spec.
    # UUIDs can be generated at http://www.itu.int/ITU-T/asn1/cgi-bin/uuid_generate.
    # If :disabled is true, the service will respond with a HTTP 503 status code.
    # Enabled status can be turned off and on using 
    #    
    def initialize(opts={})
      @sd = {:sdversion => '1.0'}.merge(opts)
      raise Error, "JSON-RPC service must have an :sdversion of 1.0" if @sd[:sdversion] != '1.0'
      raise Error, "JSON-RPC service must have a :name" if @sd[:name].blank?
      raise Error, "JSON-RPC service must have an :id" if @sd[:id].blank?
      @procs = {}
      self.add_procedure :name => 'system.describe', :proc => lambda { system_describe },
                         :return => {:type => 'obj'}
      @disabled = opts[:disabled]
    end
    
    
    #
    # Adds a procedure to the service.
    #
    def add_procedure(opts={})
      name = opts[:name]
      raise Error, "JSON-RPC procedure must have a name" if name.blank?
      proc = opts[:proc]
      raise Error, "JSON-RPC procedure must specify a :proc to be executed locally" if proc.blank?
      begin
        proc = proc.to_proc
      rescue Exception => e
        raise Error, ":proc argument could not be converted to a proc (#{e.message})"
      end
      opts[:proc] = proc
      # Canonicalise opts[:params]. We use strings internally, since parameter names will be 
      # passed as such.
      opts[:params] = (opts[:params] || []).collect do |p|
        if p.is_a?(String)
          {:name => p.to_s, :type => 'any'}
        else
          {:name => p[:name].to_s, :type => (p[:type] || 'any').to_s}
        end
      end
      # Canonicalise opts[:return]
      opts[:return] = if opts[:return]
        {:type => (opts[:return][:type] || 'any').to_s}
      else
        {:type => 'any'}
      end
      # Register the new procedure with the service
      self.procs[name] = opts
      # Empty the system.describe cache
      @sd_cache = nil
      # Finally return the procedure's call name
      name
    end
    
    
    #
    # Return a system description as a JSON Object (i.e. a Ruby hash).
    # Cached for efficiency.
    #
    def system_describe
      return @sd_cache if @sd_cache
      sd = {:sdversion => @sd[:sdversion], :name => @sd[:name], :id => @sd[:id]}
      sd[:version] = @sd[:version] if @sd[:version]
      sd[:summary] = @sd[:summary] if @sd[:summary]
      sd[:help] = @sd[:help] if @sd[:help]
      sd[:address] = @sd[:address] if @sd[:address]
      sd[:procs] = []
      @procs.each do |name, prop|
        next if name == 'system.describe'
        pd = {:name => name}
        pd[:summary] = prop[:summary] if prop[:summary]
        pd[:help] = prop[:help] if prop[:help]
        pd[:idempotent] = prop[:idempotent] if prop[:idempotent]
        pd[:params] = prop[:params] if prop[:params]
        pd[:return] = prop[:return] if prop[:return]
        sd[:procs] << pd
      end
      @sd_cache = sd
    end
    
    
    #
    # Receives a Rails request. Constructs a Get, Post or Erroneous object.
    # Evaluates the call.
    #
    def process(*args)
      req = Request.create self, *args
      req.apply
      req
    end
    
    
    #
    # This class encapsulates a request to the JSON-RPC server. It has two
    # main subclasses, Get and Post, and an auxiliary one, Erroneous (for
    # requests which are too garbled to decipher).
    #
    class Request
    
      attr_reader :status_code
    
    
      #
      # This class method takes a request and returns a Get object if the 
      # request is a GET, a Post object if the request is a POST, and an 
      # Erroneous otherwise. If the request is erroneous (which applies 
      # to all three classes), it will be marked as such.
      #
      def self.create(service, req, par)
        par = par.clone
        if req.get?
          Get.new service, req, par
        elsif req.post?
          Post.new service, req, par
        else
          Erroneous.new service, req, par, 999, 'Only POST and GET supported'
        end
      end


      #
      # Initialises the request and checks that the request as received
      # from the client conforms to the HTTP header requirements common
      # to both GET and POST requests. If the request is non-conforming,
      # marks it as erroneous.
      #
      def initialize(service, req, par)
        @service = service
        @req = req
        par.delete 'controller'     # We don't want this in our arg list
        par.delete 'action'         # We don't want this in our arg list
        @par = par
        @id = nil
        @fun ||= nil
        @args_pos = []
        @args_named = {}
        @result = nil
        @error = nil
        @status_code = nil          # Set to non-NIL if not 200
        set_error(999, "User-Agent header not specified") and return unless req.env['HTTP_USER_AGENT']
        set_error(999, "Accept header must be application/json") and return unless req.env['HTTP_ACCEPT'] == 'application/json'
      end
    
    
      #
      # Associates an error with a request. Only the first error is
      # recorded.
      #
      def set_error(error_code, msg, status_code=nil)
        return if @error
        @error = {:code => error_code, :message => msg} 
        @status_code = status_code || 500
      end
    
    
      #
      # Get the arguments in shape: convert everything to a positional arglist.
      # Processes the named parameters, storing their values in the
      # positional arglist according to the procedure declaration data.
      # Always type-checks the result.
      #
      def canonicalise_args(fun)
        procpars = fun[:params] || {}
        if procpars.size == 0 && @args_named.size > 0
          set_error 999, "Parameters passed to method declared to take none."
          return
        end
        # Go through the declared arglist and populate the positional arglist
        procpars.each_with_index do |pp, i|
          argname = pp[:name]
          argtype = pp[:type]
          arg_named = @args_named.delete argname
          arg_numbered = @args_named.delete i.to_s
          set_error(999, "You cannot set the parameter #{argname} both by name and position") and return if arg_named && arg_numbered
          arg = @args_pos[i] || arg_named || arg_numbered
          # Type-check arg
          case argtype
          when 'bit'
            set_error(999, "The arg #{argname} must be literally true or false (was #{arg.to_json})") and return unless arg == true || arg == false
          when 'num'
            if !arg.is_a?(Numeric)
              if arg.is_a?(String) && (arg_conv = arg.to_i rescue nil).to_s == arg
                arg = arg_conv
              elsif arg.is_a?(String) && (arg_conv = arg.to_f rescue nil).to_s == arg
                arg = arg_conv
              else
                set_error(999, "The arg #{argname} must be numeric (was #{arg.to_json})") 
                return
              end
            end
          when 'str'
            if !arg.is_a?(String)
              if arg.is_a?(Numeric)
                arg = arg.to_s
              else
                set_error(999, "The arg #{argname} must be a string (was #{arg.to_json})")
                return
              end
            end
          when 'arr'
            set_error(999, "The arg #{argname} must be an array (was #{arg.to_json})") and return unless arg.is_a?(Array)
          when 'obj'
            set_error(999, "The arg #{argname} must be a JSON object (was #{arg.to_json})") and return unless arg.is_a?(Hash)
          end
          # Set the positional arg
          @args_pos[i] ||= arg
        end
        # The positional arglist should now be populated. The named arglist should be exhausted.
        set_error(999, "Excess parameters passed (#{@args_named.to_json})") and return unless @args_named.size == 0
      end
      

      #
      # Expects method and args to be set up: calls the method.
      #
      def apply
        return if @error
        fun = @service.procs[@fun]
        get = self.is_a?(Get)
        set_error(999, "This JSON-RPC service does not provide a '#{@fun}' method.", (get ? 404 : 500)) and return unless fun
        set_error(999, "This method is not idempotent and can only be called using POST.") and return if get && !fun[:idempotent]
        canonicalise_args fun
        return if @error
        begin
          @result = fun[:proc].call *@args_pos
        rescue Exception => e
          set_error 999, e.message + e.backtrace.join("\n")
        end
        # If the procedure return type is the string "nil", return nothing
        @result = nil if fun[:return][:type] == 'nil'
      end


      #
      # This method returns JSON ready to send to the client, after the result
      # has been computed (which may have resulted in an error).
      #
      def response
        response_parts = []
        response_parts << '"version": "1.1"'
        response_parts << '"id": ' + @id.to_json if @id
        if @error
          response_parts << '"error": ' + {:name => 'JSONRPCError'}.merge(@error).to_json
        else
          response_parts << '"result": ' + @result.to_json
        end
        '{' + response_parts.join(', ') + "}\n"             
      end


      #
      # An instance of this class is returned when the request is a GET.
      # Upon initialisation, the request is parsed according to the specifications
      # of a JSON-RPC GET request.
      #
      class Get < Request
        def initialize(service, req, par)
          @fun = par[:method]
          par.delete 'method'       # We don't want this in our arg list
          super service, req, par
          set_error 999, "Bad call" and return unless @fun.length == 1
          @fun = @fun[0]
          query_string = get_query_string 
          return if query_string.blank?
          query_string.split('&').each do |pair|
            arg, val = pair.split("=")
            val ||= ''            
            val = URI::decode(val).gsub('+', ' ')
            case old = @args_named[arg]
            when Array:  old << val
            when nil:    @args_named[arg] = val
            else        
              @args_named[arg] = [old, val]
            end
          end
          # Note that no suppression of 'nil' and 'false' is done for GET requests (only for POSTs)
        end
        
        private
        
        #
        # This private method obtains the query string from the request, for later
        # splitting into arg names and values.
        #
        def get_query_string
          qs = @req.env['QUERY_STRING']
          # Lighty's fcgi-bindings use its 404 handler and it doesn't provide QUERY_STRING
          if qs.blank? && @req.env['SERVER_SOFTWARE'] =~ /lighttpd/
            match = @req.env['REQUEST_URI'].match(/\?(.*)/)
            qs = match[1] if match
          end 
          qs
        end
        
      end


      #
      # An instance of this class is returned when the request is a POST.
      # Upon initialisation, the request is parsed according to the specifications
      # of a JSON-RPC POST request.
      #
      class Post < Request
        def initialize(service, req, par)
          super service, req, par
          set_error(999, "Content-Type header must be application/json") and return unless req.env['CONTENT_TYPE'] == 'application/json'
          begin
            body = JSON.parse req.raw_post
          rescue Exception => e
            set_error 999, "JSON did not parse" 
            return
          end
          set_error 999, 'JSON-RPC client protocol version must be specified in POSTs' and return unless body["version"]
          @id = body["id"]
          @fun = body["method"]
          set_error 999, 'Method not specified' and return unless @fun
          args = body["params"]
          case args
          when Array
            @args_pos = args
          when Hash
            @args_named = args
          else
            set_error 999, 'Params must be JSON Object or Array' and return if args && !args.is_a?(Hash) && !args.is_a?(Array)
          end
        end
      end


      #
      # An instance of this class is returned by JsonRpc::Request.create 
      # when the request neither is a GET nor a POST.
      #
      class Erroneous < Request
        def initialize(service, req, par, code, msg)
          super service, req, par
          set_error code, msg
        end
      end

    end # of Request
  end # of Service
end # of JsonRpcService
