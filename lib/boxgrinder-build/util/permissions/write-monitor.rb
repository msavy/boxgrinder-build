#
# Copyright 2012 Red Hat, Inc.
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

require 'thread'
require 'observer'
require 'pathname'
require 'singleton'
require 'thread'

module BoxGrinder
  class WriteMonitor
    include Singleton
    include Observable

    def initialize
      @flag =  Mutex.new
      @lock_a = Mutex.new
      @lock_b = Mutex.new
      set_hooks
    end

    # Start capturing the paths of any File write. Providing a block
    # automatically stops the capture process after the terminating scope.
    #
    # This version is fairly blunt. If write() or write_nonblock() has not
    # yet been reached by the end of the block{}/stop(), then the IO will
    # be missed.
    def capture(*observers, &block)
      @lock_a.synchronize do
        add_observers(observers)
        _capture(&block)

        if block_given?
          yield
          _stop
        end
      end
    end

    # Explicitly stop capturing paths of File writes
    # Use this if you do not use `capture` with a block
    def stop
      @lock_a.synchronize { _stop }
    end

    # Stop any capturing and delete observers
    def reset
      @lock_a.synchronize do
        _stop
        delete_observers
      end
    end

    # Add a path string, this is called from the IO write() method.
    def add_path(p)
      @lock_b.synchronize do
        raise "No observers set!" if count_observers.zero?
        changed(true)
        notify_observers(:command => :add_paths, :data => realpath(p))
      end
    end

    private # Not threadsafe

    def _capture
      # Our hooks will all check this same atomic lock.
      @flag.lock
    end

    def _stop
      @flag.unlock
      changed(true)
      notify_observers(:command => :stop_capture)
    end

    def set_hooks
      eigen_capture(File, [:open, :new], @flag) do |klazz, path, mode, *other|
        add_path(path) if klazz == File && mode =~ /^(w|a)[+]?$/
      end

      eigen_capture(Dir, :mkdir, @flag) do |klazz, path, *other|
        add_path(root_dir(path))
      end

      eigen_capture(File, [:rename, :symlink, :link], @flag) do |klazz, old, new, *other|
        add_path(new)
      end
    end

    def eigen_capture(klazz, m_sym, flag, &blk)
      # Get virtual class
      v_klazz = (class << klazz; self; end)
      instance_capture(v_klazz, m_sym, flag, &blk)
    end

    def instance_capture(klazz, m_sym, flag, &blk)
      Array(m_sym).each{ |sym| alias_and_capture(klazz, sym, flag, &blk) }
    end

    def alias_and_capture(klazz, m_sym, flag, &blk)
      alias_m_sym = "__alias_#{m_sym}"

      klazz.class_eval do
        alias_method alias_m_sym, m_sym

        define_method(m_sym) do |*args, &blx|
         response = send(alias_m_sym, *args, &blx)
         blk.call(self, *args) if flag.locked?
         response
        end
      end
    end

    def add_observers(observers)
      observers.each{ |o| add_observer(o) }
    end

    def realpath(path)
      Pathname.new(path).realpath.to_s
    end

    def root_dir(relpath)
      r = relpath.match(%r(^[/]?.+?[/$]))
      return relpath if r.nil?
      r[0] || relpath
    end
  end
end