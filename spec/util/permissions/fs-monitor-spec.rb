require 'boxgrinder-build/util/permissions/fs-monitor'

module BoxGrinder
  describe FSMonitor do     

    before(:each) do
      # Singleton
      @fs_monitor = FSMonitor.instance
    end

    after(:each) do
      # Reset the singleton to avoid tests being serial
      @fs_monitor.reset
    end

    subject{ @fs_monitor }
 
    let(:observer){ mock('FSObserver-mock-1', :respond_to? => true) }
    let(:observer_2){ mock('FSObserver-mock-2', :respond_to? => true) }

    context "after singleton #initialize" do
      its(:reset){ should be_nil }
      its(:stop){ should be_false }
    
      it "should insert wrappers for File{#open, #new, #rename, #symlink, #link}, 
         Dir#mkdir." do
        File.should respond_to(:__alias_open, :__alias_new, :__alias_rename, 
          :__alias_symlink, :__alias_link)
        File.should respond_to(:open, :new, :rename, :symlink, :link)
        Dir.should respond_to(:__alias_mkdir)
        Dir.should respond_to(:mkdir)
      end
    end

    context "#capture" do
      let(:mock_return){ mock('mock_return_value') }
      let(:dumb_observer){ mock('dumb_observer').as_null_object }
      let(:dumb_observer_2){ mock('dumb_observer_2').as_null_object }
      
      before(:each) do
        # Just reflect the path back so we can differentiate the paths
        subject.stub(:realpath){|reflect| reflect}
      end

      it "should add observers to its observer set" do
        expect {
          subject.capture(dumb_observer, dumb_observer_2){}
        }.to change(subject, :count_observers).
          from(0).to(2)
      end

      def basic_capture_test_setup(klazz=File, meth_s=:open, &blk)
        klazz.stub("__alias_#{meth_s}").and_return(mock_return)

        observer.should_receive(:update).twice.ordered.
          with({ :command => :stop_capture })

        blk.call(observer)
      end

      it "should not capture outside of #capture block{}" do
        basic_capture_test_setup do |observer|
          # Ignore unscoped operations
          observer.should_receive(:update).once.
            with({ :data => '/a/y/r/s', :command => :add_path })

          File.open('/m/a/s', 'w+')

          subject.capture(observer) do 
            File.open('/a/y/r/s', 'a') 
          end

          File.open('/c/y/s', 'w')
        end
      end

      it "should capture with manual #start, #stop delimiters" do
        basic_capture_test_setup do |observer|
          observer.should_receive(:update).once.
            with({ :data => '/m/a/w', :command => :add_path })

          File.open('no-capture', 'w+')
          
          # Note: without block, hence no auto-stop
          subject.capture(observer) 
          File.open('/m/a/w', 'a') 
          subject.stop

          File.open('capture-no', 'w')
        end        
      end
      
      def wrapper_spec_builder(klazz, method, pnum, include, exclude=[], &blk)
        basic_capture_test_setup(klazz, method) do |observer|

          include.each do |arg|
            observer.should_receive(:update).once.
              with({ :data => arg[pnum], :command => :add_path})       
          end

          subject.capture(observer) do
            (include+exclude).each{ |arg| klazz.send(method, *arg) }
          end
        end
      end

      let(:mode_new_inc) do
          [['/ham/jam', 'a+'], ['/ham/jam', 'a'], 
          ['/spam', 'w+'], ['/spam', 'w']] 
      end

      let(:mode_new_exc){ [['/nocapture', 'r']] }

      it "should capture File#new when mode=/^(t|b)?((w|a)[+]?)(t|b)?$/" do
        wrapper_spec_builder(File, :new, 0, mode_new_inc, 
          mode_new_exc)
      end

      it "should capture File#open when mode=/^(t|b)?((w|a)[+]?)(t|b)?$/" do
        wrapper_spec_builder(File, :open, 0, mode_new_inc, 
          mode_new_exc)
      end
      
      it "should capture File#rename new path" do
        wrapper_spec_builder(File, :rename, 1, 
          # original -> expectation
          [['/old/path', '/new/path']])
      end

      it "should capture File#symlink" do
        wrapper_spec_builder(File, :symlink, 1,
          [['/some/file', '/the/symlink']])
      end

      it "should capture File#link" do
        wrapper_spec_builder(File, :link, 1,
          [['/some/file', '/the/hardlink']])
      end

      it "should capture Dir#mkdir" do
        basic_capture_test_setup(Dir, :mkdir) do |observer|
          observer.should_receive(:update).once.
            with({ :data => '/a_new_dir/', :command => :add_path })
          
          subject.capture(observer) do
            Dir.mkdir('/a_new_dir/and/other/junk')
          end
        end
      end
    end

    context "#add" do      
      context "invalid usage" do
        it "should raise an exception when no observers are provided" do
          expect{ subject.add_path('/exploding/sausage') }.
            to raise_error(RuntimeError)
        end
      end

      context "valid usage" do
        before(:each) do
          subject.stub(:realpath).and_return('/custard/creme')
          # Stub the 'real' method, use generated wrapper.
          Dir.stub(:__alias_mkdir).and_return(0)
        end

        # NOTE: Normally #stop would only be received once, but due to
        # resetting in after(:each) it is received twice in these
        # specs.
        it "should send captured paths to observers when capturing stopped" do
          observer.should_receive(:update).once.
            with({ :data => '/custard/creme', :command => :add_path }) 

          observer.should_receive(:update).twice.
            with({ :command => :stop_capture })

          subject.capture(observer){ Dir.mkdir('custard/creme') }
        end

        it "should accept and update multiple observers" do
          [observer, observer_2].each do |o| 
            o.should_receive(:update).once.
              with({ :data => '/custard/creme', :command => :add_path })
          end

          [observer, observer_2].each do |o| 
            o.should_receive(:update).twice.
              with({ :command => :stop_capture }) 
          end

          subject.capture(observer, observer_2) do
            Dir.mkdir('custard/creme')
          end
        end
      end
    end
  end
end
