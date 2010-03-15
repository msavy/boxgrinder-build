require 'boxgrinder-build/images/vmware-image'
require 'rspec-helpers/rspec-config-helper'
require 'rbconfig'

module BoxGrinder
  describe VMwareImage do
    include RSpecConfigHelper

    before(:all) do
      @arch = RbConfig::CONFIG['host_cpu']
    end

    def prepare_image
      params = OpenStruct.new
      params.base_vmdk = "../src/base.vmdk"
      params.base_vmx  = "../src/base.vmx"

      @config           = generate_config( params )
      @appliance_config = generate_appliance_config

      @image = VMwareImage.new( @config, @appliance_config, :log => Logger.new('/dev/null') )

      @exec_helper = @image.instance_variable_get(:@exec_helper)
    end

    it "should calculate good CHS value for 1GB disk" do
      c, h, s, total_sectors = VMwareImage.new( generate_config, generate_appliance_config ).generate_scsi_chs(1)

      c.should == 512
      h.should == 128
      s.should == 32
      total_sectors.should == 2097152
    end

    it "should calculate good CHS value for 40GB disk" do
      c, h, s, total_sectors = VMwareImage.new( generate_config, generate_appliance_config ).generate_scsi_chs(40)

      c.should == 5221
      h.should == 255
      s.should == 63
      total_sectors.should == 83886080
    end

    it "should calculate good CHS value for 160GB disk" do
      c, h, s, total_sectors = VMwareImage.new( generate_config, generate_appliance_config ).generate_scsi_chs(160)

      c.should == 20886
      h.should == 255
      s.should == 63
      total_sectors.should == 335544320
    end

    it "should change vmdk data (vmfs)" do
      prepare_image

      vmdk_image = @image.change_vmdk_values("vmfs")

      vmdk_image.scan(/^createType="(.*)"\s?$/).to_s.should == "vmfs"

      disk_attributes = vmdk_image.scan(/^RW (.*) (.*) "(.*)-sda.raw" (.*)\s?$/)[0]

      disk_attributes[0].should == "2097152"
      disk_attributes[1].should == "VMFS"
      disk_attributes[2].should == "valid-appliance"
      disk_attributes[3].should == ""

      vmdk_image.scan(/^ddb.geometry.cylinders = "(.*)"\s?$/).to_s.should == "512"
      vmdk_image.scan(/^ddb.geometry.heads = "(.*)"\s?$/).to_s.should == "128"
      vmdk_image.scan(/^ddb.geometry.sectors = "(.*)"\s?$/).to_s.should == "32"

      vmdk_image.scan(/^ddb.virtualHWVersion = "(.*)"\s?$/).to_s.should == "4"
    end

    it "should change vmdk data (flat)" do
      prepare_image

      vmdk_image = @image.change_vmdk_values("monolithicFlat")

      vmdk_image.scan(/^createType="(.*)"\s?$/).to_s.should == "monolithicFlat"

      disk_attributes = vmdk_image.scan(/^RW (.*) (.*) "(.*)-sda.raw" (.*)\s?$/)[0]

      disk_attributes[0].should == "2097152"
      disk_attributes[1].should == "FLAT"
      disk_attributes[2].should == "valid-appliance"
      disk_attributes[3].should == "0"

      vmdk_image.scan(/^ddb.geometry.cylinders = "(.*)"\s?$/).to_s.should == "512"
      vmdk_image.scan(/^ddb.geometry.heads = "(.*)"\s?$/).to_s.should == "128"
      vmdk_image.scan(/^ddb.geometry.sectors = "(.*)"\s?$/).to_s.should == "32"

      vmdk_image.scan(/^ddb.virtualHWVersion = "(.*)"\s?$/).to_s.should == "3"
    end

    it "should change vmx data" do
      prepare_image

      vmx_file = @image.change_common_vmx_values

      vmx_file.scan(/^guestOS = "(.*)"\s?$/).to_s.should == (@arch == "x86_64" ? "otherlinux-64" : "linux")
      vmx_file.scan(/^displayName = "(.*)"\s?$/).to_s.should == "valid-appliance"
      vmx_file.scan(/^annotation = "(.*)"\s?$/).to_s.should == "This is a summary | Version: 1.0 | Built by: BoxGrinder 1.0.0"
      vmx_file.scan(/^guestinfo.vmware.product.long = "(.*)"\s?$/).to_s.should == "valid-appliance"
      vmx_file.scan(/^guestinfo.vmware.product.url = "(.*)"\s?$/).to_s.should == "http://www.jboss.org/stormgrind/projects/boxgrinder.html"
      vmx_file.scan(/^numvcpus = "(.*)"\s?$/).to_s.should == "1"
      vmx_file.scan(/^memsize = "(.*)"\s?$/).to_s.should == "256"
      vmx_file.scan(/^log.fileName = "(.*)"\s?$/).to_s.should == "valid-appliance.log"
      vmx_file.scan(/^scsi0:0.fileName = "(.*)"\s?$/).to_s.should == "valid-appliance.vmdk"
    end

    it "should build personal image" do
      prepare_image

      @image.should_receive(:create_hardlink_to_disk_image).once.with("build/appliances/#{@arch}/fedora/12/valid-appliance/vmware/personal/valid-appliance-sda.raw")
      File.should_receive(:open).once.with("build/appliances/#{@arch}/fedora/12/valid-appliance/vmware/personal/valid-appliance.vmx", "w")
      File.should_receive(:open).once.with("build/appliances/#{@arch}/fedora/12/valid-appliance/vmware/personal/valid-appliance.vmdk", "w")

      @image.build_vmware_personal
    end

    it "should build enterprise image" do
      prepare_image

      @image.should_receive(:create_hardlink_to_disk_image).once.with("build/appliances/#{@arch}/fedora/12/valid-appliance/vmware/enterprise/valid-appliance-sda.raw")
      @image.should_receive(:change_common_vmx_values).with(no_args()).and_return("")

      File.should_receive(:open).once.with("build/appliances/#{@arch}/fedora/12/valid-appliance/vmware/enterprise/valid-appliance.vmx", "w")
      File.should_receive(:open).once.with("build/appliances/#{@arch}/fedora/12/valid-appliance/vmware/enterprise/valid-appliance.vmdk", "w")

      @image.build_vmware_enterprise
    end

    it "should convert image to vmware" do
      prepare_image

      @exec_helper.should_receive(:execute).with( "cp build/appliances/#{@arch}/fedora/12/valid-appliance/raw/valid-appliance/valid-appliance-sda.raw build/appliances/#{@arch}/fedora/12/valid-appliance/vmware/valid-appliance-sda.raw" )
      @image.should_receive(:customize).with(no_args())

      @image.convert_to_vmware
    end

    it "should customize image" do
      prepare_image

      customize_helper_mock = mock("ApplianceCustomizeHelper")
      ApplianceCustomizeHelper.should_receive(:new).with( @config, @appliance_config, "build/appliances/#{@arch}/fedora/12/valid-appliance/vmware/valid-appliance-sda.raw" ).and_return(customize_helper_mock)
      customize_helper_mock.should_receive(:customize).with(no_args())

      @image.customize
    end

    it "should execute post operations" do
      prepare_image

      guestfs_mock = mock("GuestFS")

      @appliance_config.post.vmware.push("one", "two", "three")

      guestfs_mock.should_receive(:sh).once.ordered.with("one")
      guestfs_mock.should_receive(:sh).once.ordered.with("two")
      guestfs_mock.should_receive(:sh).once.ordered.with("three")

      @image.execute_post_operations(guestfs_mock)
    end

    it "should install vmware tools" do
      prepare_image

      customize_helper_mock = mock("ApplianceCustomizeHelper")
      customize_helper_mock.should_receive(:install_packages).once.with("build/appliances/#{@arch}/fedora/12/valid-appliance/vmware/valid-appliance-sda.raw", {:packages=>{:yum=>["kmod-open-vm-tools"]}, :repos=>["http://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-stable.noarch.rpm", "http://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-stable.noarch.rpm"]})

      @image.install_vmware_tools( customize_helper_mock )
    end
  end
end
