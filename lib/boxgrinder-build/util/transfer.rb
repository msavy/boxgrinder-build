module BoxGrinder::Transfer
  class TransferPlugin
    @@plugins = {}
    attr_accessor :src_uri, :opts

    Dir[File.dirname(__FILE__) + "/transfer/*.rb"].each { |file| require file }

    def self.lookup(uri)
      uri = URI.parse(uri) 
      return @@plugins['copy'] if uri.scheme.nil?
      
      if not (plugin = @@plugins[uri.scheme])
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
  
  class UnsupportedProtocol < StandardError; end

  def self.open(uri, opts = {}, &blk)
    plugin = TransferPlugin::lookup(uri).new
    if block_given?
      begin
        plugin.open(uri, opts)
        yield plugin
      ensure
        plugin.close
      end
    end
    plugin
  end
end
