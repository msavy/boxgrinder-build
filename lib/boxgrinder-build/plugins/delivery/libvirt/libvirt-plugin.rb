#
# Copyright 2010 Red Hat, Inc.
#
# This is free software; you can redistribute it and/or modify it
# under the terms of the GNU Lesser General Public License as
# published by the Free Software Foundation; either version 3 of
# the License, or (at your option) any later version.
#
# This software is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this software; if not, write to the Free
# Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA
# 02110-1301 USA, or see the FSF site: http://www.fsf.org.

require 'boxgrinder-build/plugins/base-plugin'
require 'boxgrinder-build/plugins/delivery/libvirt/libvirt-capabilities'

require 'libvirt'
require 'net/sftp'
require 'fileutils'
require 'uri'
require 'etc'
require 'builder'
require 'ostruct'

module BoxGrinder
  class LibVirtPlugin < BasePlugin

    def set_defaults
      set_default_config_value('script', false)
      set_default_config_value('image_delivery_uri', '/var/lib/libvirt/images/')
      set_default_config_value('graphics', 'none')
      set_default_config_value('no_auto_console', true)
      set_default_config_value('network', 'default')
      # Disable certificate verification procedures by default
      set_default_config_value('remote_no_verify', true)
      set_default_config_value('bus', false)
      set_default_config_value('overwrite', false)
      set_default_config_value('default_permissions', 0644)
      set_default_config_value('dump_xml', false)
      set_default_config_value('domain_type', false)
      set_default_config_value('virt_type', false)
      set_default_config_value('undefine_existing', false)

      validate_plugin_config(['libvirt_hypervisor_uri'])
      patch
    end

    def validate
      set_defaults

      @libvirt_capabilities = LibVirtCapabilities.new(:log => @log)

      # Optional user provided script
      @script = @plugin_config['script']
      @image_delivery_uri = URI.parse(@plugin_config['image_delivery_uri'])

      # Do not connect to the livirt hypervisor, just assume sensible defaults
      @dump_xml = @plugin_config['dump_xml']

      # The path that the image will be accessible at on the {remote, local} libvirt
      # If not specified we assume it is the same as the @image_delivery_uri. It is valid
      # that they can be different - for instance the image is delivered to a central repository
      # by SSH that maps to a local mount on host using libvirt.
      @libvirt_image_uri = (@plugin_config['libvirt_image_uri'] ||= @image_delivery_uri.path)

      @network = @plugin_config['network']
      @domain_type = @plugin_config['domain_type']
      @virt_type = @plugin_config['virt_type']
      @undefine_existing = @plugin_config['undefine_existing']

      # no_verify determines whether certificate validation performed
      @remote_no_verify = @plugin_config['remote_no_verify'] ? 1 : 0

      @libvirt_hypervisor_uri = @plugin_config['libvirt_hypervisor_uri'] << "?no_verify=#{@remote_no_verify}"
      @bus = @plugin_config['bus']
      @appliance_name = "#{@appliance_config.name}-#{@appliance_config.version}.#{@appliance_config.release}-#{@appliance_config.os.name}-#{@appliance_config.os.version}-#{@appliance_config.hardware.arch}-#{current_platform}"
    end

    def execute
      if @image_delivery_uri.scheme =~ /(sftp|scp)/
        @log.info("Assuming this is a remote address.")
        upload_image
      else
        @log.info("Copying disk #{@previous_deliverables.disk} to: #{@image_delivery_uri.path}")
        FileUtils.cp(@previous_deliverables.disk, @image_delivery_uri.path)
      end

      if @dump_xml
        @log.info("Determining locally only.")
        xml = determine_locally
      else
        @log.info("Determining remotely.")
        xml = determine_remotely
      end
      write_xml(xml)
    end

    def determine_remotely
      conn = Libvirt::open(@libvirt_hypervisor_uri)
      if dom = get_existing_domain(conn, @appliance_name)
        unless @undefine_existing
          @log.fatal("A domain already exists with the name #{@appliance_name}. Set undefine_existing:true to automatically destroy and undefine it.")
          raise RuntimeError, "Domain '#{@appliance_name}' already exists"  #Make better specific exception
        end
        @log.info("Undefining existing domain #{@appliance_name}")
        undefine_domain(dom)
      end

      guest = @libvirt_capabilities.determine_capabilities(conn, @previous_plugin_info)
      raise "Remote libvirt machine offered no viable guests!" if guest.nil?

      xml = build_xml(guest)
      @log.info("Defining domain #{@appliance_name}")
      conn.define_domain_xml(xml)
      xml
    ensure
      if conn
        conn.close unless conn.closed?
      end
    end

    # If we just want to dump a basic XML skeleton and provide sensible defaults
    def determine_locally()
      domain = @libvirt_capabilities.get_plugin(@previous_plugin_info).domain_rank.last
      build_xml(OpenStruct.new({
        :domain_type => domain.name,
        :os_type => domain.virt_rank.last,
        :bus => domain.bus
      }))
    end

    # Remote only
    def upload_image
      uploader = SFTPPlugin.new
      uploader.instance_variable_set(:@log, @log)

      #SFTP library automagically uses keys registered with the OS first before trying a password.
      uploader.connect(@image_delivery_uri.host,
      (@image_delivery_uri.user ||= Etc.getlogin),
      @image_delivery_uri.password)

      uploader.upload_files(@image_delivery_uri.path,
                            @plugin_config['default_permissions'],
                            @plugin_config['overwrite'],
                            File.basename(@previous_deliverables.disk) => @previous_deliverables.disk)
    ensure
      uploader.disconnect if uploader.connected?
    end

    def build_xml(guest)
      _build_xml(:domain_type => (@domain_type || guest.domain_type),
                :os_type => (@virt_type || guest.os_type),
                :bus => (@bus || guest.bus))
    end

    def _build_xml(options = {})
      {:bus => @bus, :domain_type => @previous_plugin_info[:name], :os_type => :hvm}.merge!(options)

      builder = Builder::XmlMarkup.new(:indent => 2)

      xml = builder.domain(:type => options[:domain_type].to_s) do |domain|
        domain.name(@appliance_name)
        domain.description(@appliance_config.summary)
        domain.memory(@appliance_config.hardware.memory * (1024**2))
        domain.vcpu(@appliance_config.hardware.cpus)
        domain.os do |os|
          os.type(options[:os_type].to_s, :arch => @appliance_config.hardware.arch)
          os.boot(:dev => 'hd')
        end
        domain.devices do |devices|
          devices.disk(:type => 'file', :device => 'disk') do |disk|
            disk.source(:file => "#{@libvirt_image_uri}/#{File.basename(@previous_deliverables.disk)}")
            disk.target(:dev => 'hda', :bus => options[:bus].to_s)
          end
          devices.interface(:type => 'network') do |interface|
            interface.source(:network => @network)
          end
        end
        domain.features do |features|
          features.pae if @appliance_config.os.pae
        end
      end

      @log.debug xml

      # Let the user modify the XML specification to their requirements
      if @script
        @log.info "Attempting to run user provided script for modifying libVirt XML..."
        xml = IO::popen("#{script} #{xml}").read
        @log.debug "Response was: #{xml}"
      end
      xml
    end

    def get_existing_domain(conn, name)
      return conn.lookup_domain_by_name(name)
    rescue Libvirt::Error => e
      return nil if e.libvirt_code == 42 # If domain not defined
      raise # Otherwise reraise
    end

    def undefine_domain(dom)
      case dom.info.state
        when Libvirt::Domain::RUNNING, Libvirt::Domain::PAUSED, Libvirt::Domain::BLOCKED
          dom.destroy
      end
      dom.undefine
    end

    # Current libvirt library provides no way of getting the libvirt_code for
    # errors, this patches it in.
    def patch
      # If an update fixes this, do nothing.
      return if Libvirt::Error.respond_to?(:libvirt_code, false)
        Libvirt::Error.module_eval do
          def libvirt_code; @libvirt_code end
        end
    end

    def write_xml(xml)
      fname = "#{@appliance_name}.xml"
      puts fname
      File.open("#{@dir.tmp}/#{fname}",'w'){|f| f.write(xml)}
      register_deliverable(:xml => fname)
    end
  end
end

plugin :class => BoxGrinder::LibVirtPlugin, :type => :delivery, :name => :libvirt, :full_name => "libVirt Virtualisation API"