module BoxGrinder
  module EBS
    module Messages
      def block_device_mapping_message
<<-DOC 
#{%(Since version 0.10.2 BoxGrinder no longer *attaches* or *mounts* any ephemeral 
disks by default for EBS AMIs.).bold}

It is still possible to specify attachment points at build-time if 
you desire by using: 
  #{%(--delivery-config block_device_mappings:"/dev/sdb=ephemeral0:/dev/sdc=ephemeral").bold}

You can also specify your block device mappings at launch-time.
 
See the following resource for full details, including an outline of terminology 
and differing strategies for attaching and mounting: 
  #{%(http://www.boxgrinder.org/permalink/ephemeral#ebs).bold}
DOC
      end
    end
  end
end
