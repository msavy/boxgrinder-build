require 'boxgrinder-build/plugins/base-plugin'
require 'boxgrinder-build/helpers/command-helper'
require 'boxgrinder-build/util/transfer'
require 'active_support/core_ext/hash/deep_merge'
require 'open4'
require 'libvirt'

module BoxGrinder
  class LibvirtPlugin < BasePlugin
    plugin(:type => :delivery, 
           :name => :libvirt, 
           :full_name => "libvirt Virtualisation API", 
           :require_root => false)

    autoload(:Errors, 'boxgrinder-build/plugins/delivery/libvirt/errors')
    
    DEFAULT_PATH  = '/var/lib/libvirt/images'

    OCTAL_CASTER  = {
      :aliases => [:octal],
      :patterns => [/^0?[1-7][0-7]*$/],
      :cast => lambda { |v, _| v.to_i(8) }
    }

    ALIASES       = {
      :connection_uri => %w(connection_uri connect),
      :image_delivery_uri => %w(image_delivery_uri image-delivery-uri),
      :libvirt_image_uri => %w(libvirt_image_uri image-image-uri),
      :remote_no_verify => %w(remote_no_verify remote-no-verify),
      :name => %w(name appliance_name appliance-name),
      :disk => %w(disk),
      :virt_type => %w(virt-type virt_type domain-type domain_type),
      :default_permissions => %w(default_permissions default-permissions),
      :overwrite => %w(overwrite)
    }

    NO_AUTO_MERGE = ALIASES.values.flatten

    def validate
      nstr = [@appliance_config.name, @appliance_config.version, 
              @appliance_config.release, @appliance_config.os.name, 
              @appliance_config.os.version, @appliance_config.hardware.arch,
              current_platform].join('-')
      
      @name = 
        set_default_config_value(ALIASES[:name], nstr, :type => :string)
      
      @image_delivery_uri = 
        set_default_config_value(ALIASES[:image_delivery_uri],
                                 DEFAULT_PATH,
                                 :type => :string) do |_, v|
          URI.parse(v)
        end
      
      @libvirt_image_uri = 
        set_default_config_value(ALIASES[:libvirt_image_uri],
                                 @image_delivery_uri.path,
                                 :type => :string)
   
      @remote_no_verify = 
        set_default_config_value(ALIASES[:remote_no_verify], 
                                 true, 
                                 :type => :string)
      
      @connection_uri = 
        set_default_config_value(ALIASES[:connection_uri], 
                                 '',
                                 :type => :string) do |_, v|
          unless v.empty?  
            v << (v.include?('?') ? '&' : '?') << "no_verify=#{rnv}"
          end
          URI.parse(v)
        end

      @virt_type = 
        set_default_config_value(ALIASES[:virt_type], false, :type => :hash)

      @default_permissions = 
        set_default_config_value(ALIASES[:default_permissions], 
                                 0664,
                                 :type => :octal,
                                 :caster => OCTAL_CASTER)
      
      @overwrite = 
        set_default_config_value(ALIASES[:overwrite], false, :type => :bool)

      @disk =
        set_default_config_value(ALIASES[:disk], false, :type => :hash) do |_, v|
          basename       = File.basename(@previous_deliverables.disk)
          disk_location  = {
            :disk => {
              :path => File.join(@libvirt_image_uri, basename)
             }
          }
        disk_location[:disk].deep_merge!(v || {})
        disk_location
        end
    end

    def execute 
      manage_existing_domain(@name)

      deliver_image(@image_delivery_uri,
                    @previous_deliverables.disk,
                    @image_delivery_uri.path, 
                    :overwrite => @overwrite,
                    :permissions => @default_permissions)
      
      register_image
    end

    private
    def register_image
      args = {
        'connect' => @connection_uri,
        'name' => @name,
        'description' => @appliance_config.summary,
        'ram' => @appliance_config.hardware.memory,
        'vcpus' => @appliance_config.hardware.cpus,
        'boot' => 'hd',
        'import' => nil,
        'noautoconsole' => nil,
        'force' => nil
      }

      update_args(args, @virt_type)
      update_args(args, @disk)

      automerge = @plugin_config.reject{ |k, v| NO_AUTO_MERGE.include?(k) }
      
      args.update(automerge)
      
      lv_cmd = CommandHelper::hash_to_command('virt-install',
                                              args, 
                                              ["="],
                                              [","])

      @log.debug "Libvirt command: #{lv_cmd}."

      stdout, stderr = '', ''
      status = Open4::spawn(lv_cmd, 
                            'stdout' => stdout, 
                            'stderr' => stderr)

      @log.info stdout.strip
    rescue Open4::SpawnError
      Errors::virt_error_handler(stderr)
    rescue Errno::ENOENT 
      @log.fatal "virt-install not found, ensure it is available."
      raise
    end

    def update_args(hash, update)
      hash.update(update) if update
    end

    def deliver_image(uri, f_src, f_dest, opts = {})
      Transfer::open(uri.to_s) do |plugin|
        plugin.transfer(f_src.to_s, f_dest.to_s, opts)
      end
    end

    def manage_existing_domain(name)
      if(domain = get_existing_domain(libvirt_connection, name))
        unless @overwrite
          @log.fatal "A domain already exists with the name #{name}. " <<
            "Set overwrite:true to automatically destroy and undefine it."

          raise Errors::DomainAlreadyDefinedError, "#{name} already defined."
        end
        undefine_domain(domain)
      end
    end

    def libvirt_connection
      uri = URI::Generic.build(:scheme => @connection_uri.scheme, 
                               :userinfo => @connection_uri.user,
                               :host => @connection_uri.host,
                               :path => @connection_uri.path,
                               :query => @connection_uri.query).to_s

      @conn ||= Libvirt::open_auth(uri, [Libvirt::CRED_AUTHNAME,
                                         Libvirt::CRED_PASSPHRASE]) do |cred|
        case cred["type"]
        when Libvirt::CRED_AUTHNAME
          @connection_uri.user
        when Libvirt::CRED_PASSPHRASE
          @connection_uri.password
        end
      end
    end

    # Look up a domain by name
    def get_existing_domain(conn, name)
      return conn.lookup_domain_by_name(name)
    rescue Libvirt::Error => e
      return nil if e.libvirt_code == 42 # If domain not defined
      raise # Otherwise reraise
    end

    # Undefine a domain. The domain will be destroyed first if required.
    def undefine_domain(dom)
      case dom.info.state
        when Libvirt::Domain::RUNNING, Libvirt::Domain::PAUSED, 
        Libvirt::Domain::BLOCKED
          dom.destroy
      end
      dom.undefine
    end

    # Libvirt library in older version of Fedora provides no way of getting the
    # libvirt_code for errors, this patches it in.
    def libvirt_code_patch
      return if Libvirt::Error.respond_to?(:libvirt_code, false)
      Libvirt::Error.module_eval do
        def libvirt_code; @libvirt_code end
      end
    end
  end
end
