require 'set'

module BoxGrinder
  describe FSObserver do
    let(:init_filterset){ Set.new([%r(^/(etc|dev|sys|bin|sbin|etc|lib|lib64|boot|run|proc|selinux)/)]) }
 
    before(:each) do
      @paths = []
      @fs_observer = FSObserver.new('some-usr', 'some-grp')
    end
      
    subject{ @fs_observer }
    
    its(:path_set){ should be_empty }
    its(:filter_set){ should eq init_filterset }

    describe "#initialize" do
      it "should merge extra :path" do
        fso = FSObserver.new('j', 'u', :paths => '/a/b/c')
        fso.path_set.should eql(Set.new(['/a/b/c']))
      end

      it "should merge extra :path array" do
        fso = FSObserver.new('i', 'c', :paths => ['a/b/c', '/d/e/f'])
        fso.path_set.should eql(Set.new(['a/b/c','/d/e/f']))
      end
    end
  end
end
