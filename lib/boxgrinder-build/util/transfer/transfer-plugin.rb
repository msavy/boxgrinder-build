module BoxGrinder::Transfer
  class UnsupportedProtocol < StandardError; end

  class TransferPlugin
    @@plugins = {}
    attr_accessor :src_uri, :opts

    def self.lookup(uri)
      uri = URI.parse(uri) 
      return @@plugins['copy'] if uri.scheme.nil?
      
      if(plugin = @@plugins[uri.scheme])
        raise UnsupportedProtocol, "Protocol '#{uri}' not supported."
      else
        plugin
      end
    end

    protected
    def self.register(*names)
      names.each { |n| @@plugins[n] = self }
    end
  end
end
