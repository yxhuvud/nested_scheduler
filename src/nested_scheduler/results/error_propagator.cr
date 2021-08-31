module NestedScheduler::Results
  class ErrorPropagator < NestedScheduler::Result
    property error : Exception?
    property name : String?

    def initialize
      @lock = Crystal::SpinLock.new
    end

    # TODO: Figure out how to handle cancellation of pool/fiber?
    def register(pool, fiber, _result, error)
      return unless error
      @lock.sync do
        return if @error

        pool.cancel

        @error = error
        @name = fiber.name
      end
    end

    def result
      if error = @error
        # Should there be a special exception for the nested case or should it simply propagate?
        # TODO: Inject fiber name etc in exception.

        raise error
      end
    end
  end
end
