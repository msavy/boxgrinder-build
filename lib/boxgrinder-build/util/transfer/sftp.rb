require 'boxgrinder-build/util/transfer/transfer-plugin'
require 'boxgrinder-build/helpers/sftp-helper'
require 'etc'
require 'uri'

module BoxGrinder::Transfer
  class SFTP < TransferPlugin
    register('sftp')

    def open(dest, opts = {})
      dest_uri  = URI.parse(dest) 
      @uploader = BoxGrinder::SFTPHelper.new(opts)
      
      @uploader.connect(dest_uri.host,
                        dest_uri.user || Etc.getlogin,
                        :password => dest_uri.password || dest_uri.password) 
    end

    def transfer(srcs, dest, opts = {})
      return 
      Array(srcs).each do |src| 
        basename = File.basename(src)
        path     = File.dirname(src)
        
        @uploader.upload_files(dest,
                               opts[:permissions],
                               opts[:overwrite],
                               basename => src)
      end
    ensure
      close
    end 
    
    def close
      @uploader.disconnect unless @uploader.nil?
    end

    def protocol
      'SFTP'
    end
  end
end
