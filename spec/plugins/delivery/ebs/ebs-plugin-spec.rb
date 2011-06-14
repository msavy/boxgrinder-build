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
require 'ostruct'
require 'logger'
require 'boxgrinder-build/plugins/delivery/ebs/ebs-plugin'
require 'hashery/opencascade'

module BoxGrinder

  describe EBSPlugin do
    before(:all) do
      @arch = `uname -m`.chomp.strip
    end

    def prepare_plugin
      @plugin = EBSPlugin.new

      yield @plugin if block_given?

      @config = mock('Config')
      @config.stub!(:delivery_config).and_return({})
      plugins = mock('Plugins')
      plugins.stub!(:[]).with('ebs').and_return({})
      @config.stub!(:[]).with(:plugins).and_return(plugins)

      @appliance_config = mock('ApplianceConfig')

      @appliance_config.stub!(:name).and_return('appliance_name')
      @appliance_config.stub!(:version).and_return(1)
      @appliance_config.stub!(:release).and_return(0)
      @appliance_config.stub!(:os).and_return(OpenCascade.new({:name => 'fedora', :version => '14'}))
      @appliance_config.stub!(:hardware).and_return(OpenCascade.new({:arch => 'x86_64', :base_arch => 'x86_64'}))
      @appliance_config.stub!(:path).and_return(OpenCascade.new({:build => '/a/build/path'}))

      @plugin = @plugin.init(
          @config,
          @appliance_config,
          :log => Logger.new('/dev/null'),
          :plugin_info => {:class => BoxGrinder::EBSPlugin, :type => :delivery, :name => :ebs, :full_name => "Elastic Block Storage"},
          :config_file => "#{File.dirname(__FILE__)}/ebs.yaml"
      )

      @plugin_config = @plugin.instance_variable_get(:@plugin_config).merge(
          {
              'access_key' => 'access_key',
              'secret_access_key' => 'secret_access_key',
              'bucket' => 'bucket',
              'account_number' => '0000-0000-0000',
              'cert_file' => '/path/to/cert/file',
              'key_file' => '/path/to/key/file'
          }
      )

      @plugin.instance_variable_set(:@plugin_config, @plugin_config)
    end

    it "should register all operating systems with specific versions" do
      Resolv.stub!(:getname).with("169.254.169.254").and_return([".ec2.internal"])

      prepare_plugin do |plugin|
        avaibility_zone = mock('AZ')
        avaibility_zone.should_receive(:string).and_return('avaibility-zone1')

        plugin.should_receive(:open).with('http://169.254.169.254/latest/meta-data/placement/availability-zone').and_return(avaibility_zone)
      end

      supported_oses = @plugin.instance_variable_get(:@supported_oses)

      supported_oses.size.should == 3
      supported_oses.keys.sort.should == ['fedora', 'rhel', 'centos'].sort
      supported_oses['rhel'].should == ['6']
      supported_oses['fedora'].should == ['13', '14', '15']
      supported_oses['centos'].should == ['5']
    end

    describe ".after_init" do
      it "should set default avaibility zone to current one" do
        Resolv.stub!(:getname).with("169.254.169.254").and_return([".ec2.internal"])

        prepare_plugin do |plugin|
          availability_zone = mock('AZ')
          availability_zone.should_receive(:string).and_return('availability-zone1')

          plugin.should_receive(:open).with('http://169.254.169.254/latest/meta-data/placement/availability-zone').and_return(availability_zone)
        end

        @plugin.instance_variable_get(:@plugin_config)['availability_zone'].should == 'availability-zone1'
      end

      it "should not set default availability zone because we're not on EC2" do
        Resolv.stub!(:getname).with("169.254.169.254").and_return(["bleh"])

        prepare_plugin

        @plugin.instance_variable_get(:@plugin_config)['availability_zone'].should == nil
      end
    end

    describe '.ami_info' do

      it "should check if image is already registered and return false if there are no images registered for this account" do
        prepare_plugin { |plugin| plugin.stub!(:after_init) }

        plugin_config = mock('PluginConfig')
        plugin_config.should_receive(:[]).with('account_number').and_return('0000-0000-0000')

        @plugin.instance_variable_set(:@plugin_config, plugin_config)

        ec2 = mock('EC2')
        ec2.should_receive(:describe_images).with(:owner_id => '000000000000')

        @plugin.instance_variable_set(:@ec2, ec2)

        @plugin.ami_info('aname').should == false
      end

      it "should check if image is already registered and return false if there are no images with name aname_new" do
        prepare_plugin { |plugin| plugin.stub!(:after_init) }

        plugin_config = mock('PluginConfig')
        plugin_config.should_receive(:[]).with('account_number').and_return('0000-0000-0000')

        @plugin.instance_variable_set(:@plugin_config, plugin_config)

        ec2 = mock('EC2')
        ec2.should_receive(:describe_images).with(:owner_id => '000000000000').and_return({'imagesSet' => {'item' => [{'name' => 'abc', 'imageId' => '1'}, {'name' => 'aname', 'imageId' => '2'}]}})

        @plugin.instance_variable_set(:@ec2, ec2)

        @plugin.ami_info('aname_new').should == false
      end

      it "should return valid AMI information map for a single matching image when a valid imageId exists" do
        prepare_plugin { |plugin| plugin.stub!(:after_init) }

        plugin_config = mock('PluginConfig')
        plugin_config.should_receive(:[]).with('account_number').and_return('0000-0000-0000')

        @plugin.instance_variable_set(:@plugin_config, plugin_config)

        ec2 = mock('EC2')
        ec2.should_receive(:describe_images).with(:owner_id => '000000000000').and_return({'imagesSet' => {'item' => [{'name' => 'abc', 'imageId' => '1'}, {'name' => 'aname', 'imageId' => '2'}]}})

        @plugin.instance_variable_set(:@ec2, ec2)

        @plugin.ami_info('aname').should == {'name' => 'aname', 'imageId' => '2'}
      end

    end

    describe '.already_registered?' do

      it "should check if image is already registered and return true image is registered" do
        Resolv.stub!(:getname).with("169.254.169.254").and_return([".ec2.internal"])

        prepare_plugin { |plugin| plugin.stub!(:after_init) }

        plugin_config = mock('PluginConfig')
        plugin_config.should_receive(:[]).with('account_number').and_return('0000-0000-0000')

        @plugin.instance_variable_set(:@plugin_config, plugin_config)

        ec2 = mock('EC2')
        ec2.should_receive(:describe_images).with(:owner_id => '000000000000').and_return({'imagesSet' => {'item' => [{'name' => 'abc', 'imageId' => '1'}, {'name' => 'aname', 'imageId' => '2'}]}})

        @plugin.instance_variable_set(:@ec2, ec2)

        @plugin.already_registered?('aname').should == '2'
      end

    end

    it "should adjust fstab" do
      prepare_plugin { |plugin| plugin.stub!(:after_init) }

      guestfs = mock('GuestFS')

      guestfs.should_receive(:sh).with("cat /etc/fstab | grep -v '/mnt' | grep -v '/data' | grep -v 'swap' > /etc/fstab.new")
      guestfs.should_receive(:mv).with("/etc/fstab.new", "/etc/fstab")

      @plugin.adjust_fstab(guestfs)
    end

    it "should get a new free device" do
      prepare_plugin { |plugin| plugin.stub!(:after_init) }

      File.should_receive(:exists?).with("/dev/sdf").and_return(false)
      File.should_receive(:exists?).with("/dev/xvdf").and_return(false)

      @plugin.free_device_suffix.should == "f"
    end

    it "should get a new free device next in order" do
      prepare_plugin { |plugin| plugin.stub!(:after_init) }

      File.should_receive(:exists?).with("/dev/sdf").and_return(false)
      File.should_receive(:exists?).with("/dev/xvdf").and_return(true)
      File.should_receive(:exists?).with("/dev/sdg").and_return(false)
      File.should_receive(:exists?).with("/dev/xvdg").and_return(false)

      @plugin.free_device_suffix.should == "g"
    end

    it "should return true if on EC2" do
      Resolv.stub!(:getname).with("169.254.169.254").and_return([".ec2.internal"])

      prepare_plugin { |plugin| plugin.stub!(:after_init) }

      @plugin.valid_platform?.should == true
    end

    it "should return false if NOT on EC2" do
      Resolv.stub!(:getname).with("169.254.169.254").and_return(["bleh"])

      prepare_plugin { |plugin| plugin.stub!(:after_init) }

      @plugin.valid_platform?.should == false
    end

    describe ".ebs_appliance_name" do
      it "should return basic appliance name" do
        prepare_plugin { |plugin| plugin.stub!(:after_init) }
        @plugin.ebs_appliance_name.should == "appliance_name/fedora/14/1.0/x86_64"
      end

      it "should always return basic appliance name when overwrite is enabled, but snapshot is disabled" do
        prepare_plugin { |plugin| plugin.stub!(:after_init) }
        @plugin_config.merge!('overwrite' => true, 'snapshot' => false)
        @plugin.ebs_appliance_name.should == "appliance_name/fedora/14/1.0/x86_64"
      end

      it "should still return a valid _initial_ snapshot appliance name, even if overwrite and snapshot are enabled on first ever run" do
        prepare_plugin { |plugin| plugin.stub!(:after_init) }

        @plugin_config.merge!('overwrite' => true, 'snapshot' => true)

        ec2 = mock('EC2')
        ec2.should_receive(:describe_images).once.with(:owner_id => '000000000000').and_return(nil)#should be nothing

        @plugin.instance_variable_set(:@ec2, ec2)

        @plugin.ebs_appliance_name.should == "appliance_name/fedora/14/1.0-SNAPSHOT-1/x86_64"
      end

      it "should return 2nd snapshot of appliance" do
        prepare_plugin { |plugin| plugin.stub!(:after_init) }

        @plugin_config.merge!('snapshot' => true)

        ec2 = mock('EC2')
        ec2.should_receive(:describe_images).twice.with(:owner_id => '000000000000').and_return({'imagesSet' => {'item' => [
            {'imageId' => '1', 'name' => 'appliance_name/fedora/14/1.0/x86_64'},
            {'imageId' => '2', 'name' => 'appliance_name/fedora/14/1.0-SNAPSHOT-1/x86_64'}
        ]}})

        @plugin.instance_variable_set(:@ec2, ec2)

        @plugin.ebs_appliance_name.should == "appliance_name/fedora/14/1.0-SNAPSHOT-2/x86_64"
      end

      it "should return the last snapshot name again when OVERWRITE is enabled" do
        prepare_plugin { |plugin| plugin.stub!(:after_init) }

        @plugin_config.merge!('snapshot' => true, 'overwrite' => true)

        ec2 = mock('EC2')
        ec2.should_receive(:describe_images).twice.with(:owner_id => '000000000000').and_return({'imagesSet' => {'item' => [
            {'imageId' => '1', 'name' => 'appliance_name/fedora/14/1.0/x86_64'},
            {'imageId' => '2', 'name' => 'appliance_name/fedora/14/1.0-SNAPSHOT-1/x86_64'}
        ]}})

        @plugin.instance_variable_set(:@ec2, ec2)

        @plugin.ebs_appliance_name.should == "appliance_name/fedora/14/1.0-SNAPSHOT-1/x86_64"
      end

    end

    describe ".stomp_ebs" do

      before(:each) do
        @ami_info =  recursive_ostruct({'imageId' => 'sleepy', 'blockDeviceMapping' => {'item' => [{'deviceName' => '/dev/sda1', 'ebs' => {'snapshotId' => 'bashful'}}]}})
        @dummy_instances = recursive_ostruct([{'instanceId' => 'grumpy'},
                             {'instanceId' => 'sneezy'}])
        @dummy_snapshot = recursive_ostruct({'snapshotId' => 'bashful', 'volumeId' => 'snow-white'})
      end

      it "should return false if there was no block device found" do
        prepare_plugin do |plugin|
          plugin.stub!(:after_init)
          plugin.stub!(:block_device_from_ami).and_return(nil)
        end
        @plugin.stomp_ebs(@ami_info).should == false
      end


      it "should throw an exception if there is still an EBS instance[s] running when an overwrite is requested" do
        prepare_plugin do |plugin|
          plugin.stub!(:after_init)
          plugin.stub!(:snapshot_info).and_return(@dummy_snapshot)
          plugin.stub!(:get_instances).and_return(@dummy_instances)
        end
       lambda { @plugin.stomp_ebs(@ami_info) }.should raise_error(RuntimeError)
      end

      it "should detach and delete the block store, remove the snapshot and deregister the image" do
        prepare_plugin do |plugin|
          plugin.stub!(:after_init)
          plugin.stub!(:snapshot_info).and_return(@dummy_snapshot)
          plugin.stub!(:get_instances).and_return(false)
        end

        ec2 = mock('EC2')
        ec2.should_receive(:detach_volume).with(:volume_id => 'snow-white', :force => true)
        ec2.should_receive(:delete_volume).with(:volume_id => 'snow-white')
        ec2.should_receive(:deregister_image).with(:image_id => 'sleepy')
        ec2.should_receive(:delete_snapshot).with(:snapshot_id => 'bashful')

        @plugin.instance_variable_set(:@ec2, ec2)
        @plugin.stomp_ebs(@ami_info)
      end

      it "should not delete AWS snapshots when preserve_snapshots is set" do
        prepare_plugin do |plugin|
          plugin.stub!(:after_init)
          plugin.stub!(:snapshot_info).and_return(@dummy_snapshot)
          plugin.stub!(:get_instances).and_return(false)
        end

        @plugin_config.merge!('preserve_snapshots' => true)

        ec2 = mock('EC2')
        ec2.should_receive(:detach_volume).with(:volume_id => 'snow-white', :force => true)
        ec2.should_receive(:delete_volume).with(:volume_id => 'snow-white')
        ec2.should_receive(:deregister_image).with(:image_id => 'sleepy')
        ec2.should_not_receive(:delete_snapshot).with(:snapshot_id => 'bashful')

        @plugin.instance_variable_set(:@ec2, ec2)
        @plugin.stomp_ebs(@ami_info)
      end

    end

    #Amazon-EC2 gem uses recursive ostructs, in a subtly different and wont work with opencascade
    #this replicates the format to avoid breaking the code in tests.
    def recursive_ostruct(initial)
      clone = initial.clone
      ostruct = case initial.class
        when Array
          clone.collect! do |v|
            recursive_ostruct v
          end
        when Hash
           clone.each_pair do |k,v| #follow down until reach terminal
            clone[k] = recursive_ostruct v
           end
          return OpenStruct.new clone
        else
          return clone
        end
      ostruct
    end
  end
end

