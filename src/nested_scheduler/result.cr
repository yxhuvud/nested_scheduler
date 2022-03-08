module NestedScheduler
  abstract class Result
    abstract def initialize
    abstract def register_error(pool, fiber, error)
    abstract def result
    abstract def init(&block : -> _) : ->

    def reraise_on_error
      if error = @error
        error.prepend_current_callstack
        # TODO: Add a line to callstack that explains that it is a nested
        # raise.
        # TODO: Inject fiber name etc in exception.

        raise error
      else
        yield
      end
    end
  end
end
