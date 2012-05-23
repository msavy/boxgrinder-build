require 'boxgrinder-build'
require 'boxgrinder-build/option-parser'
require 'boxgrinder-build/appliance'
require 'boxgrinder-build/util/permissions/fs-observer'
require 'boxgrinder-build/util/permissions/fs-monitor'

require 'boxgrinder-core/models/config'
require 'boxgrinder-core/helpers/log-helper'

module BoxGrinder
  class CLI
    def self.start 
      options  = OptionParser.parse_opts
      config   = Config.new(options)

      BoxGrinder.ensure_root

      observer = config.change_to_user && FSObserver.new(config.uid, config.gid)
      # observer = if(config.change_to_user)
      #              FSObserver.new(config.uid, config.gid)
      #            else
      #              nil
      #            end

      FSMonitor.instance.capture(observer)

      log = LogHelper.new(:level => config.log_level)

      begin
        appliance = Appliance.new(config[:appliance_definition_file], 
                                  config, 
                                  :log => log)

        appliance.create
      rescue Exception => e
        msg = "#{e.class}: #{e.message}#$/#{e.backtrace.join($/)}"
      if options.backtrace
        log.fatal msg
      else # demote backtrace to debug so that it is in file log only
        log.fatal("#{e.class}: #{e.message}. See the log file for detailed " +
                  "information.")
        log.debug msg
      end
      ensure
        FSMonitor.instance.stop
      end
    rescue Exception => e
      $stderr.puts "#{e.message}"
      raise
    end
  end 
end  
