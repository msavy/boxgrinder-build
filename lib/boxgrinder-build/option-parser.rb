require 'trollop'
require 'hashery/opencascade'
require 'boxgrinder-build/version'

module BoxGrinder::OptionParser
  PROGRAM       = File.basename($0)
  USAGE_BANNER  = <<EOB.gsub(/^[ ]{4}/, '')
    Usage: #{PROGRAM} [appliance definition file] [options]

    A tool for building VM images from simple definition files.
        
    Homepage:
        http://boxgrinder.org/

    Documentation:
        http://boxgrinder.org/tutorials/

    Examples:
        $ #{PROGRAM} jeos.appl                                                           # Build KVM image for jeos.appl
        $ #{PROGRAM} jeos.appl -f                                                        # Build KVM image for jeos.appl with removing previous build for this image
        $ #{PROGRAM} jeos.appl --os-config format:qcow2                                  # Build KVM image for jeos.appl with a qcow2 disk
        $ #{PROGRAM} jeos.appl -p vmware --platform-config type:personal,thin_disk:true  # Build VMware image for VMware Server, Player, Fusion using thin (growing) disk
        $ #{PROGRAM} jeos.appl -p ec2 -d ami                                             # Build and register AMI for jeos.appl
        $ #{PROGRAM} jeos.appl -p vmware -d local                                        # Build VMware image for jeos.appl and deliver it to local directory
EOB

  def self.parse_opts
    opts = Trollop::options do
      version("BoxGrinder Build #{BoxGrinder::Version::STRING} #{$/} " +
              "#{BoxGrinder::Version::plugin_info}")

      banner USAGE_BANNER
      
      banner ''
      banner 'Options:'

      opt(:platform, 
          'Platform to convert given appliance to.', 
          :type => :string)

      opt(:delivery, 'Delivery method for given appliance.', :type => :string)

      opt(:force, 
          'Force image recreation. Removes all previous builds for given ' +
          'appliance.', 
          :type => :boolean, 
          :default => false)

      opt(:config, 'Plugin configuration options defined via YAML file.', 
          :type => :string)
      
      banner ''
      banner 'Plugin Configuration Options:'

      opt(:plugins, 
          'Additional plugins (format: plugin1,plugin2).',
          :type => :string)
      
      opt(:os_config, 
          'Operating System plugin configuration ' +
          '(format: key1:value1,key2:value2).', 
          :type => :strings)

      opt(:platform_config, 
          'Platform plugin configuration (format: key1:value1,key2:value2).',
          :type => :strings)

      opt(:delivery_config, 
          'Delivery plugin configuration (format: key1:value1,key2:value2).',
          :type => :strings)
      
      banner ''
      banner 'Logging Options:'

      opt(:trace, 'Use trace logging.', :type => :boolean, :default => false)
      opt(:debug, 'Use debug logging.', :type => :boolean, :default => false)
      conflicts(:debug, :trace)

      opt(:backtrace, 
          'Print full backtraces (No effect if --trace or --debug).', 
          :type => :boolean, 
          :default => false)

      banner ''
      banner 'Other:'
     
      opt(:change_to_user, 
          'Switch to local user when root not required.', 
          :default => false)
    end
    
    validate_directed_dependencies(opts,
                                   :platform_config => :platform, 
                                   :delivery_config => :delivery)

    validate_logging(opts)
    validate_subconfig(opts)
    validate_appliance_definition_file(opts)

    default_hash([:os_config, :platform_config, :delivery_config], opts)
    as_symbol([:platform, :delivery], opts)
    default_array([:plugins], opts)
    internal_rename(opts, :plugins => :additional_plugins)

    OpenCascade.new(opts)
  end

  private

  def self.validate_directed_dependencies(opts, dependencies)
    dependencies.each_pair do |tail, head|
      if opts[tail] && !opts[head]
        Trollop::die(tail, "without specifying a #{head} plugin") 
      end
    end
  end

  def self.validate_appliance_definition_file(opts)
    if ARGV.empty? or ARGV.size > 1
      Trollop::die('No or more than one appliance definition file specified.')
    end
    
    unless File.exists?(opts[:appliance_definition_file] = ARGV.shift)
      Trollop::die("Appliance definition file '#{appliance_definition_file}' " +
                   "could not be found.")
    end
  end

  def self.validate_logging(opts)
    [:debug, :trace].each { |l| opts[:log_level] = l.to_sym if opts[l] }
  end

  # Parse, then validate and assign
  def self.validate_subconfig(opts)
    [:os_config, :platform_config, :delivery_config].each do |config|
      if opts[config]
        opts[config] = split_arguments(opts[config].join, config)
        opts[config] = split_pairs(opts, config)
      end
    end
  end

  SPLIT_ASSIGN = Oniguruma::ORegexp.new('(?<key>.*?(?<!\\\\)):(?<value>.*)')
  SEPARATOR    = ','

  def self.split_pairs(opts, name)
    opts[name].reduce({}) do |accum, pair|
      if(match = SPLIT_ASSIGN.match(pair))
        accum.update(match[:key].strip => match[:value].strip)
      else
        Trollop::die(name, "Invalid format. Use key1:value1,key2:value2. " + 
                     "Colon literal characters can be escaped as '\\:'")
      end
    end
  end

  ## Supports JSON-ish values, in addition to standard k1,v1:k2,v2
  def self.split_arguments(str, name, args = [])
    result = parse_json(str, name)

    args.push(result[0].split(SEPARATOR).map(&:strip))    

    if(result.size > 1)
      args.push(result[1])
      return split_arguments(result[2], name, args)
    end

    args.flatten.reject { |r| r.empty? }
  end

  def self.parse_json(str, name)
    brace_left      = '{'
    brace_left_idx  = nil
    brace_right     = '}'
    brace_right_idx = nil

    balancer = str.each_char.each_with_index.inject(nil) do |accum, (char, index)|
      case char
      when brace_left
        accum = (accum || 0) + 1
        brace_left_idx ||= index
      when brace_right
        accum = (accum || 0) - 1
        brace_right_idx = index
      end
      break accum if accum == 0 # Found a valid json mapping
      accum
    end

    if(brace_left_idx.nil? || brace_right_idx.nil?)
      return [str]
    end

    if(balancer < 0 || balancer > 0)
      Trollop::die(name, "Brace imbalance in '#{str}'")
    end

    json_key_idx = find_key(str, brace_left_idx)

    [
     str[0 .. (json_key_idx - 1)],
     str[json_key_idx .. brace_right_idx],
     str[(brace_right_idx + 1) .. -1]
    ]
  end

  def self.find_key(str, brace_left_idx)
    brace_left_idx.downto(0) do |index|
      return (index + 1) if str[index].chr == SEPARATOR
    end
    nil
  end

  # These are just to maintain compataibility with the old layout for now
  # Probably better to encapsulate config in future to shield it from 
  # implementation detail changes.
  def self.internal_rename(opts, aliases = {})
    aliases.inject(opts) do |hash, (k, v)| 
      hash[v] = hash[k] 
      hash.delete(k)
    end
  end

  def self.default_array(params, opts)
    cast(params, opts) { |hash, k, v| v || [] }
  end

  def self.default_hash(params, opts)
    cast(params, opts) { |hash, k, v| v || {} }
  end

  def self.as_symbol(params, opts)
    cast(params, opts) { |hash, k, v| v && v.to_sym }
  end

  def self.cast(params, opts)
    Array(params).inject(opts) do |hash, (k, v)| 
      hash[k] = yield hash, k, v
      hash
    end
  end
end  
