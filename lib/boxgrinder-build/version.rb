module BoxGrinder::Version
  STRING = '0.11.0' # placeholder

  def self.plugin_info
    [:os, :platform, :delivery].inject("#{$/}") do |accum, type|
      accum << "Available #{type} plugins:"
      BoxGrinder::PluginManager.instance.plugins[type].each do |name, plugin_info|
        accum << " - #{name} plugin for #{plugin_info[:full_name]}"
      end
      accum
    end
  end
end
