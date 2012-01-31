require 'set'

module BoxGrinder
  describe FSObserver do
    let(:empty_set){ Set.new }
    let(:init_filterset){ Set.new([%r(^/(etc|dev|sys|bin|sbin|etc|lib|lib64|boot|run|proc|selinux)/)]) }
 
    before(:each) do
      @fs_observer = FSObserver.new('some-usr', 'some-grp')
    end
      
    subject{ @fs_observer }
    
    its(:path_set){ should be_empty }
    its(:filter_set){ should eq init_filterset }

    context "#initialize" do
      it "should merge extra :path" do
        fso = FSObserver.new('j', 'u', :paths => '/a/b/c')
        fso.path_set.should eql(mkset('/a/b/c'))
      end

      it "should merge extra :path array" do
        fso = FSObserver.new('i', 'c', :paths => ['a/b/c', '/d/e/f'])
        fso.path_set.should eql(mkset('a/b/c','/d/e/f'))
      end
    end

    context "#update" do
      context ":command=:add_path" do
        let(:simple_update) do 
          path_update(subject, '/the/great/escape')
        end

        it "should add the path to the path_set" do
          expect{ simple_update }.to change(subject, :path_set).
            from(empty_set).to(mkset('/the/great/escape'))
        end
        
        it "should add regex for all children of new path to the filter_set" do
          expect_set = init_filterset + mkset(%r[^/the/great/escape/])
 
          expect{ simple_update }.to change(subject, :filter_set).
            from(init_filterset).to(expect_set)
        end

        context "rejecting blacklisted and filtered paths" do
          before(:each) do
            simple_update
          end
          
          it "should not add a path if it is a duplicate" do
            expect{ simple_update }.to_not change(subject, :path_set)

            expect{ simple_update }.to_not change(subject, :filter_set)
          end

          it "should not add a path if it is pre-filtered" do
            expect{ path_update(subject, "/etc/sneaky/file") }.
              to_not change(subject, :path_set) 

            expect{ path_update(subject, "/etc/sneaky/file") }.
              to_not change(subject, :filter_set)
          end

          it "should not add a new path if it is a child of existing path" do
            expect{ path_update(subject, "/the/great/escape/900") }.
              to_not change(subject, :path_set)

            expect{ path_update(subject, "/the/great/escape/900") }.
              to_not change(subject, :filter_set)
          end
        end
      end
      
      context ":command=:stop_capture" do

        let(:update_a){ path_update(subject, '/a/path') }  
        let(:update_b){ path_update(subject, '/b/path') }        

        before(:each) do
          update_a
          update_b
        end

        context "all files exist" do
          before(:each){ File.stub(:exist?).and_return(true) }

          it "should change ownership of captured paths" do
            subject.stub(:change_user)

            FileUtils.should_receive(:chown_R).
              with('some-usr', 'some-grp', '/a/path').once

            FileUtils.should_receive(:chown_R).
              with('some-usr', 'some-grp', '/b/path').once

            subject.update({ :command => :stop_capture })
          end
          
          it "it should switch from current user (root) to standard user" do
            FileUtils.stub(:chown_R)
            
            Process::Sys.stub!(:respond_to?).and_return(true)
            
            Process::Sys.should_receive(:setresgid).
              with('some-grp', 'some-grp', 'some-grp')

            Process::Sys.should_receive(:setresuid).
              with('some-usr', 'some-usr', 'some-usr')

            subject.update({ :command => :stop_capture })
          end
        end

        it "should ignore any paths that no longer exist" do
          subject.stub(:change_user)

          File.stub(:exist?).and_return(true, false)
          
          FileUtils.should_receive(:chown_R).
              with('some-usr', 'some-grp', '/a/path').once

          update_a
          update_b
          
          subject.update({ :command => :stop_capture })
        end
      end
    end

    def path_update(subject, path)
      subject.update({ :command => :add_path, :data => path })
    end

    def mkset(*vars)
      Set.new(Array(vars))
    end
  end
end
