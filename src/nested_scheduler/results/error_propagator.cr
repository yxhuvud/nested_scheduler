module NestedScheduler::Results
  # Returns nil. Will cancel the pool on any errors and then it will
  # re-raise the error when the pool is done.
  class ErrorPropagator < NestedScheduler::Result
    property error : Exception?
    property name : String?

    def initialize
      @lock = Crystal::SpinLock.new
    end

    # TODO: Figure out how to handle cancellation of pool/fiber?
    def register_error(pool, fiber, error)
      return unless error
      @lock.sync do
        return if @error

        pool.cancel

        @error = error
        @name = fiber.name
      end
    end

    def result
      reraise_on_error { }
    end

    def init(&block : -> _) : ->
      block
    end
  end
end
