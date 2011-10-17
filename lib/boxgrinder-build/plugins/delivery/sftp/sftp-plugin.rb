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

require 'rubygems'
require 'net/ssh'
require 'net/sftp'
require 'progressbar'
require 'boxgrinder-build/plugins/base-plugin'
require 'boxgrinder-build/helpers/package-helper'

module BoxGrinder
  class SFTPPlugin < BasePlugin
    def validate
      set_default_config_value('overwrite', false)
      set_default_config_value('default_permissions', 0644)
      set_default_config_value('identity', false)

      validate_plugin_config(['path', 'username', 'host'], 'http://boxgrinder.org/tutorials/boxgrinder-build-plugins/#SFTP_Delivery_Plugin')

      @identity = (@plugin_config['identity'] || @plugin_config['i'])
    end

    def after_init
      register_deliverable(:package => "#{@appliance_config.name}-#{@appliance_config.version}.#{@appliance_config.release}-#{@appliance_config.os.name}-#{@appliance_config.os.version}-#{@appliance_config.hardware.arch}-#{current_platform}.tgz")
    end

    def execute
      PackageHelper.new(@config, @appliance_config, :log => @log, :exec_helper => @exec_helper).package( File.dirname(@previous_deliverables[:disk]), @deliverables[:package] )

      @log.info "Uploading #{@appliance_config.name} appliance via SSH..."

      #TODO move to a block
      connect(@plugin_config['host'], @plugin_config['username'], @plugin_config['password'], (@identity || generate_keypaths).to_a)
      upload_files(@plugin_config['path'], @plugin_config['default_permissions'], @plugin_config['overwrite'], File.basename(@deliverables[:package]) => @deliverables[:package])

      @log.info "Appliance #{@appliance_config.name} uploaded."
    rescue => e
      @log.error e
      @log.error "An error occurred while uploading files."
      raise
    ensure
      disconnect
    end

    def connect(host, username, password, keys=generate_keypaths)
      @log.info "Connecting to #{host}..."
      @ssh = Net::SSH.start(host, username, :password => password, :keys => keys)
    end

    def connected?
      return true if !@ssh.nil? and !@ssh.closed?
      false
    end

    def disconnect
      @log.info "Disconnecting from host..."
      @ssh.close if connected?
      @ssh = nil
    end

    # Extend the default baked paths in net-ssh/net-sftp to include SUDO_USER
    # and/or LOGNAME key directories too.
    def generate_keypaths
      keys = %w(id_rsa id_dsa)
      dirs = %w(.ssh .ssh2)
      paths = %w(~/.ssh/id_rsa ~/.ssh/id_dsa ~/.ssh2/id_rsa ~/.ssh2/id_dsa)
      ['SUDO_USER','LOGNAME'].inject(paths) do |accum, var|
        if user = ENV[var]
          accum << dirs.collect do |d|
            keys.collect { |k| File.expand_path("~#{user}/#{d}/#{k}") }
          end.flatten!
        end
        accum
      end.flatten!
      paths
    end

    def upload_files(path, default_permissions, overwrite, files = {})
      return if files.size == 0

      raise "You're not connected to server" unless connected?

      @log.debug "Files to upload:"

      files.each do |remote, local|
        @log.debug "#{File.basename(local)} => #{path}/#{remote}"
      end

      global_size = 0

      files.each_value do |file|
        global_size += File.size(file)
      end

      global_size_kb = global_size / 1024
      global_size_mb = global_size_kb / 1024

      @log.info "#{files.size} files to upload (#{global_size_mb > 0 ? global_size_mb.to_s + "MB" : global_size_kb > 0 ? global_size_kb.to_s + "kB" : global_size.to_s})"

      @ssh.sftp.connect do |sftp|
        begin
          sftp.stat!(path)
        rescue Net::SFTP::StatusException => e
          raise unless e.code == 2
          @ssh.exec!("mkdir -p #{path}")
        end

        nb = 0

        files.each do |key, local|
          name       = File.basename(local)
          remote     = "#{path}/#{key}"
          size_b     = File.size(local)
          size_kb    = size_b / 1024
          nb_of      = "#{nb += 1}/#{files.size}"

          begin
            sftp.stat!(remote)

            unless overwrite

              local_md5_sum   = `md5sum #{local} | awk '{ print $1 }'`.strip
              remote_md5_sum  = @ssh.exec!("md5sum #{remote} | awk '{ print $1 }'").strip

              if (local_md5_sum.eql?(remote_md5_sum))
                @log.info "#{nb_of} #{name}: files are identical (md5sum: #{local_md5_sum}), skipping..."
                next
              end
            end

          rescue Net::SFTP::StatusException => e
            raise unless e.code == 2
          end

          @ssh.exec!("mkdir -p #{File.dirname(remote) }")

          pbar = ProgressBar.new("#{nb_of} #{name}", size_b)
          pbar.file_transfer_mode

          sftp.upload!(local, remote) do |event, uploader, * args|
            case event
              when :open then
              when :put then
                pbar.set(args[1])
              when :close then
              when :mkdir then
              when :finish then
                pbar.finish
            end
          end

          sftp.setstat(remote, :permissions => default_permissions)
        end
      end
    end
  end
end

plugin :class => BoxGrinder::SFTPPlugin, :type => :delivery, :name => :sftp, :full_name  => "SSH File Transfer Protocol"
