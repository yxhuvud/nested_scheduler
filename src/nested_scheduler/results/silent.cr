module NestedScheduler::Results
  # Returns nil. Will ignore any exceptions in fibers.
  class Silent < NestedScheduler::Result
    def initialize
    end

    def register_error(_pool, _fiber, _error)
    end

    def result
    end

    def init(&block : -> _) : ->
      block
    end
  end
end
