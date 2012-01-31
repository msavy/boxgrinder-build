require 'thread'

class GetSet
  def initialize(initial_state=false)
    @val = initial_state
    @mutex = Mutex.new
  end

  # Atomic get-and-set.
  #
  # When used with a block, the existing value is provided as
  # an argument to the block. The block's return value sets the
  # object's value state.
  #
  # When used without a block; if a nil +set_val+ parameter is
  # provided the existing state is returned. Else the object
  # value state is set to +set_val+
  def get_set(set_val=nil, &blk)
    @mutex.synchronize do
      if block_given?
        @val = blk.call(@val)
      else
        @val = set_val unless set_val.nil?
      end
      @val
    end
  end
end