module BoxGrinder
  class LibvirtPlugin 
    module Errors
      class LibvirtError < StandardError; end
    
      class DomainAlreadyDefinedError < LibvirtError; end
      class InvalidOptionError < LibvirtError; end
      class RegistrationError < LibvirtError; end

      def self.virt_error_handler(stderr)
        case stderr
        when /error: (no such option.*)$/
          raise InvalidOptionError, $1.strip
        when /^ERROR(.+)$/
          raise RegistrationError, $1.strip
        else
          raise LibvirtError, stderr.strip
        end  
      end
    end
  end
end
