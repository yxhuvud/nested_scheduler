module NestedScheduler
  abstract class Result
    abstract def initialize
    abstract def register_error(pool, fiber, error)
    abstract def result
    abstract def init(&block : -> _) : ->
  end
end
