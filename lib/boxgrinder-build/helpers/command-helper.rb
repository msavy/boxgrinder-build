require 'escape'

module BoxGrinder::CommandHelper
  def self.hash_to_command(base_command, 
                           args = {}, 
                           eqls = [":", "="], 
                           subdivs = [",", "&"])
    
    args.each_pair.reduce(base_command) do |accum, (key, value)|
      accum << (key.to_s.size == 1 ? " -#{key}" : " --#{key}")
      accum << (build_substr(" ", value, eqls, subdivs) || "")
    end
  end
 
  def self.command_to_hash(argument_string,              
                           eqls = ["="], 
                           subdivs = ["&"])
    build_submap({}, argument_string, eqls, subdivs)
  end

  private   
  def self.build_submap(map, str, eqls, subdivs)
    return str if str.nil? || str.empty? || eqls.empty? || subdivs.empty?
    subdiv = subdivs.shift
    equals = eqls.shift

    str.split(subdiv).each do |s_pair|
      var, value = s_pair.split(equals) # /dev/xvdb=ephemeral0
      map[var] = build_submap(map, value, eqls, subdivs) # parse substring
    end
    map
  end

  def self.build_substr(str, value, eqls, subdivs)
    return nil if value.nil? || value === true

    if value.is_a?(Hash)
      if eqls.empty? || subdivs.empty?
        raise ArgumentError, "Depth exhausted subdivider/splitter characters."
      end

      c_sub, c_eql = subdivs.shift, eqls.shift
      nested = value.each_pair.collect do |k, v| 
        if(substr = build_substr("", v, eqls, subdivs))
          "#{k}#{c_eql}#{substr}" 
        else
          k.to_s
        end
      end
      str << nested.join(c_sub)
    else
      #if /\s/ =~ value.to_s
      #  str << %('#{value}')
      #else
        str << Escape::shell_single_word(value.to_s)
      #end
    end
    str
  end
end
