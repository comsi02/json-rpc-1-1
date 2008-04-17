require File.dirname(__FILE__) + '/../../../../spec/spec_helper'

plugin_spec_dir = File.dirname(__FILE__)
ActiveRecord::Base.logger = Logger.new(plugin_spec_dir + "/debug.log")

require 'spec'
require 'spec/rails'

class Hash
  
  def except(*keys)
    self.reject { |k,v| keys.include?(k || k.to_sym) }
  end
  
  def with(overrides = {})
    self.merge overrides
  end
  
  def only(*keys)
    self.reject { |k,v| !keys.include?( k || k.to_sym) }
  end
  
end

def stringify_symbols_in_hash(h)
  res = {}
  h.each do |k, v|
    res[k.to_s] = case v
                  when Hash: stringify_symbols_in_hash(v)
                  when Array: stringify_symbols_in_array(v)
                  else
                    v
                  end
  end
  res
end
def stringify_symbols_in_array(h)
  res = []
  h.each do |v|
    res << case v
           when Hash: stringify_symbols_in_hash(v)
           when Array: stringify_symbols_in_array(v)
           else
             v
           end
  end
  res
end
