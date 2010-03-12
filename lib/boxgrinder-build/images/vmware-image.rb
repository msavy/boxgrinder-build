# JBoss, Home of Professional Open Source
# Copyright 2009, Red Hat Middleware LLC, and individual contributors
# by the @authors tag. See the copyright.txt in the distribution for a
# full listing of individual contributors.
#
# This is free software; you can redistribute it and/or modify it
# under the terms of the GNU Lesser General Public License as
# published by the Free Software Foundation; either version 2.1 of
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

require 'rake/tasklib'
require 'rexml/document'
require 'boxgrinder-build/helpers/appliance-customize-helper'

module BoxGrinder

  class VMwareImage < Rake::TaskLib

    def initialize( config, appliance_config, options = {} )
      @config           = config
      @appliance_config = appliance_config

      @log          = options[:log]         || Logger.new(STDOUT)
      @exec_helper  = options[:exec_helper] || ExecHelper.new( { :log => @log } )

      define_tasks
    end

    def define_tasks
      directory @appliance_config.path.dir.vmware.build
      directory @appliance_config.path.dir.vmware.personal
      directory @appliance_config.path.dir.vmware.enterprise

      task "appliance:#{@appliance_config.name}:vmware:personal" => [ @appliance_config.path.file.vmware.disk, @appliance_config.path.dir.vmware.personal ] do
        build_vmware_personal
      end

      task "appliance:#{@appliance_config.name}:vmware:enterprise" => [ @appliance_config.path.file.vmware.disk, @appliance_config.path.dir.vmware.enterprise ] do
        build_vmware_enterprise
      end

      desc "Build #{@appliance_config.name} appliance for VMware"
      task "appliance:#{@appliance_config.name}:vmware" => [ "appliance:#{@appliance_config.name}:vmware:personal", "appliance:#{@appliance_config.name}:vmware:enterprise" ]

      file @appliance_config.path.file.vmware.disk => [ @appliance_config.path.dir.vmware.build, @appliance_config.path.file.raw.xml ] do
        convert_to_vmware
      end
    end

    # returns value of cylinders, heads and sector for selected disk size (in GB)

    def generate_scsi_chs(disk_size)
      disk_size = disk_size * 1024

      gb_sectors = 2097152

      if disk_size == 1024
        h = 128
        s = 32
      else
        h = 255
        s = 63
      end

      c = disk_size / 1024 * gb_sectors / (h*s)
      total_sectors = gb_sectors * disk_size / 1024

      return [ c, h, s, total_sectors ]
    end

    def change_vmdk_values( type )
      vmdk_data = File.open( @config.files.base_vmdk ).read

      disk_size = 0
      @appliance_config.hardware.partitions.values.each { |part| disk_size += part['size'] }

      c, h, s, total_sectors = generate_scsi_chs( disk_size )

      is_enterprise = type.eql?("vmfs")

      vmdk_data.gsub!( /#NAME#/, @appliance_config.name )
      vmdk_data.gsub!( /#TYPE#/, type )
      vmdk_data.gsub!( /#EXTENT_TYPE#/, is_enterprise ? "VMFS" : "FLAT" )
      vmdk_data.gsub!( /#NUMBER#/, is_enterprise ? "" : "0" )
      vmdk_data.gsub!( /#HW_VERSION#/, is_enterprise ? "4" : "3" )
      vmdk_data.gsub!( /#CYLINDERS#/, c.to_s )
      vmdk_data.gsub!( /#HEADS#/, h.to_s )
      vmdk_data.gsub!( /#SECTORS#/, s.to_s )
      vmdk_data.gsub!( /#TOTAL_SECTORS#/, total_sectors.to_s )

      vmdk_data
    end

    def change_common_vmx_values
      vmx_data = File.open( @config.files.base_vmx ).read

      # replace version with current appliance version
      vmx_data.gsub!( /#VERSION#/, "#{@appliance_config.version}.#{@appliance_config.release}" )
      # replace builder with current builder name and version
      vmx_data.gsub!( /#BUILDER#/, "#{@config.name} #{@config.version_with_release}" )
      # change name
      vmx_data.gsub!( /#NAME#/, @appliance_config.name.to_s )
      # and summary
      vmx_data.gsub!( /#SUMMARY#/, @appliance_config.summary.to_s )
      # replace guestOS informations to: linux or otherlinux-64, this seems to be the savests values
      vmx_data.gsub!( /#GUESTOS#/, "#{@appliance_config.hardware.arch == "x86_64" ? "otherlinux-64" : "linux"}" )
      # memory size
      vmx_data.gsub!( /#MEM_SIZE#/, @appliance_config.hardware.memory.to_s )
      # memory size
      vmx_data.gsub!( /#VCPU#/, @appliance_config.hardware.cpus.to_s )
      # network name
      # vmx_data.gsub!( /#NETWORK_NAME#/, @appliance_config.network_name )

      vmx_data
    end

    def create_hardlink_to_disk_image( vmware_raw_file )
      # Hard link RAW disk to VMware destination folder
      FileUtils.ln( @appliance_config.path.file.vmware.disk, vmware_raw_file ) if ( !File.exists?( vmware_raw_file ) || File.new( @appliance_config.path.file.raw.disk ).mtime > File.new( vmware_raw_file ).mtime )
    end

    def build_vmware_personal
      @log.debug "Building VMware personal image."

      # link disk image
      create_hardlink_to_disk_image( @appliance_config.path.file.vmware.personal.disk )

      # create .vmx file
      File.open( @appliance_config.path.file.vmware.personal.vmx, "w" ) {|f| f.write( change_common_vmx_values ) }

      # create disk descriptor file
      File.open( @appliance_config.path.file.vmware.personal.vmdk, "w" ) {|f| f.write( change_vmdk_values( "monolithicFlat" ) ) }

      @log.debug "VMware personal image was built."
    end

    def build_vmware_enterprise
      @log.debug "Building VMware enterprise image."

      # link disk image
      create_hardlink_to_disk_image( @appliance_config.path.file.vmware.enterprise.disk )

      # defaults for ESXi (maybe for others too)
      @appliance_config.hardware.network = "VM Network" if @appliance_config.hardware.network.eql?( "NAT" )

      # create .vmx file
      vmx_data = change_common_vmx_values
      vmx_data += "ethernet0.networkName = \"#{@appliance_config.hardware.network}\""

      File.open( @appliance_config.path.file.vmware.enterprise.vmx, "w" ) {|f| f.write( vmx_data ) }

      # create disk descriptor file
      File.open( @appliance_config.path.file.vmware.enterprise.vmdk, "w" ) {|f| f.write( change_vmdk_values( "vmfs" ) ) }

      @log.debug "VMware enterprise image was built."
    end

    def convert_to_vmware
      @log.info "Converting image to VMware format..."
      @log.debug "Copying VMware image file, this may take several minutes..."

      @exec_helper.execute "cp #{@appliance_config.path.file.raw.disk} #{@appliance_config.path.file.vmware.disk}" if ( !File.exists?( @appliance_config.path.file.vmware.disk ) || File.new( @appliance_config.path.file.raw.disk ).mtime > File.new( @appliance_config.path.file.vmware.disk ).mtime )

      @log.debug "VMware image copied."

      customize

      @log.info "Image converted to VMware format."
    end

    def customize
      @log.debug "Customizing VMware image..."
      ApplianceCustomizeHelper.new( @config, @appliance_config, @appliance_config.path.file.vmware.disk ).customize do |customizer, guestfs|
        # install_vmware_tools( customizer )
        execute_post_operations( guestfs )
      end
      @log.debug "Image customized."
    end

    def execute_post_operations( guestfs )
      @log.debug "Executing post commands..."
      for cmd in @appliance_config.post.vmware
        @log.debug "Executing #{cmd}"
        guestfs.sh( cmd )
      end
      @log.debug "Post commands executed."
    end

    def install_vmware_tools( customizer )
      @log.debug "Installing VMware tools..."

      if @appliance_config.is_os_version_stable?
        rpmfusion_repo_rpm = [ "http://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-rawhide.noarch.rpm", "http://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-rawhide.noarch.rpm" ]
      else
        rpmfusion_repo_rpm = [ "http://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-stable.noarch.rpm", "http://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-stable.noarch.rpm" ]
      end

      #TODO this takes about 11 minutes, need to find a quicker way to install kmod-open-vm-tools package
      customizer.install_packages( @appliance_config.path.file.vmware.disk, { :packages => { :yum => [ "kmod-open-vm-tools" ] }, :repos => rpmfusion_repo_rpm } )

      @log.debug "VMware tools installed."
    end
  end
end
