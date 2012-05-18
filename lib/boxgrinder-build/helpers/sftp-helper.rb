module BoxGrinder
  class SFTPHelper
    def initialize(options={})
      @log = options[:log] || LogHelper.new
    end

    def connect(host, username, options={})
      @log.info "Connecting to #{host}..."
      @ssh = Net::SSH.start(host, username, options)
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
