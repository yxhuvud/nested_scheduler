module NestedScheduler::Results
  # Returns an array of the specified type, in unspecified order.
  # Will cancel the pool on any errors and then it will re-raise the
  # error when the pool is done.
  class ResultCollector(T) < NestedScheduler::Result
    property error : Exception?
    property name : String?

    def initialize
      @lock = Crystal::SpinLock.new
      @results = [] of T
    end

    # TODO: Figure out how to handle cancellation of pool/fiber?
    def register_error(pool, fiber, error)
      @lock.sync do
        return if @error

        pool.cancel
        @error = error
        @name = fiber.name
      end
    end

    def result : Array(T)
      reraise_on_error { @results }
    end

    def init(&block : -> _) : ->
      Proc(Void).new do
        res = block.call
        @lock.sync do
          unless @error
            # If statement necessary due to type inference seemingly being borked in this case.
            # typeof(res) => T, but res.as(T) raises, thinking res is nilable.

            # Unfortunately I havn't been able to isolate the issue.
            if res.is_a?(T)
              @results << res
            else
              raise ArgumentError.new "Expected block to return #{T}, but got #{typeof(res)}"
            end
          end
        end
      end
    end
  end
end
