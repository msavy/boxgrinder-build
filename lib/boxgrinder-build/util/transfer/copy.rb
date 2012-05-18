require 'boxgrinder-build/util/transfer/transfer-plugin'
require 'progressbar'

module BoxGrinder::Transfer
  class Copy < TransferPlugin
    register('cp', 'copy')
    
    def open(*any); end

    def transfer(src, dest, opts = {})
      #self.class.cp(src, dest, opts)
    end

    def close; end

    def protocol
      'local copy'
    end

    def self.cp(src, dest, opts = {})
      opts = { 
        :bs => 4096, 
        :title => "Copying File", 
        :permissions => 0664 
      }.merge!(opts)

      dest = Dir.exist?(dest) ? Path.join(dest, File.basename(src)) : dest
      
      raise Errno::EEXIST if File.exists?(dest) && (!opts[:overwrite])

      src_f      = File.open(src, 'r')
      dest_f     = File.open(dest, 'w', opts[:permissions])
      size       = src_f.stat.size
      block_size = opts[:bs]
      bar        = ProgressBar.new(opts[:title], size)

      (0 .. size).step(block_size) do |position|
        read_bs = (position + block_size > size) ? size - position : block_size
        in_data = src_f.sysread(read_bs)
        dest_f.syswrite(in_data)
        bar.inc(block_size)
      end    
    ensure
      src_f.close unless src_f.nil?
      dest_f.close unless dest_f.nil?
      bar.finish unless bar.nil?
    end
  end
end
