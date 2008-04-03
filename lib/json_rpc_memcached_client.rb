class JsonRpcMemcachedClient < JsonRpcClient
  
  def self.json_rpc_service(base_uri, opts={})
    super
    @cache_obj = opts[:cache_obj] or raise 'Must define cache_obj'
    @expires = opts[:expires] || 0 
    system_describe unless @service_description
  end 

  def self.method_missing(name, *args)
    name = name.to_s
    return super if (name == 'system.describe') || !@get_procs.include?(name)
    cache_key_str = "#{@service_description['id']}:#{name}:#{args.inspect}"
    rval = @cache_obj.get(cache_key_str) 
    if rval == :MemCache_no_such_entry
      rval = super
      @cache_obj.set(cache_key_str, rval, @expires)
    end
    return rval
  end
  
end
