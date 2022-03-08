class Exception
  def prepend_current_callstack
    @callstack = Exception::CallStack.new(self)
  end
end

struct Exception::CallStack
  def initialize(template : Exception)
    if callstack = template.callstack
      @callstack = callstack.@callstack
      unwind = CallStack.unwind
      # skip lines related to stitching the stack itself.
      unwind.shift(5)
      @callstack.concat unwind
    else
      @callstack = CallStack.unwind
    end
  end
end
