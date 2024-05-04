# Recent updates 

With the amount of changes in these parts of the source and the dependency on monkeypatching things, I'll probably won't update this to work with recent versions of crystal before it stabilizes again.

The upside is that the changes that are made is generally great and will allow for better implementations. 

# nested_scheduler

Nested Scheduler is an expansion and/or replacement for the built in
fiber scheduler of Crystal. It allows setting up thread pools with one
or more dedicated threads that will handle a set of fibers. It draws
inspiration from [Notes on Structured
Concurrency](https://vorpus.org/blog/notes-on-structured-concurrency-or-go-statement-considered-harmful/)
and from [Structured Concurrency](https://250bpm.com/blog:71/). Both
articles are very much recommended read.

As such, it follows a couple of core ideas:

* Don't break abstraction. All fibers have a predefined lifetime
  defined by a section of code it can exist in and fiber lifetimes are
  strictly hierarchical - no partial overlaps. This helps by
  preventing many race conditions, but also by making silent leaks of
  fibers that never finishes executing a bit more visible.
* Simplify resource cleanup. This may sound counterintuitive in a
  language like Crystal which has a garbage collector but it turns out
  to be very nice to be able to use local variables defined in the
  surrounding scope inside a fiber without fear of it going out of
  scope. This is especially true for file handles or other resources
  that often are closed when they go out of scope (using an `ensure`
  statement)
* If there is an exception in a fiber, then the exception will by
  default be propagated and reraised in the originating context. This
  creates debuggable stacktraces with information about both what went
  wrong and how to get there.

The constructs this library provide are related to constructs like
supervisors in Erlang (a bit less powerful) and waitgroups/errgroups
in Go (a bit more powerful).

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     nested_scheduler:
       github: yxhuvud/nested_scheduler
   ```

2. Run `shards install`

## Usage

All usage of Nested Scheduler is assuming the program is compiled with
-Dpreview_mt. It will not work without it. Additionally,
`nested_scheduler` is implemented by monkeypatching many classes that
is very much core to Crystal, so beware that this can be quite fragile
if the crystal implementation changes.

### Basics

The basics of the nested scheduler is the
`NestedScheduler::ThreadPool.nursery` block. The point of that is to
spawn fibers from the yielded pool.

```crystal
require "nested_scheduler"

NestedScheduler::ThreadPool.nursery do |pool|
  pool.spawn { sleep 5 }
  pool.spawn { sleep 2 }
end
```

These fibers will execute concurrently (and potentially in parallel),
and the `nursery` method will not return unless **all** fibers in the
pool have finished. Calling `spawn` inside the block will generate a
new fiber in the *current* pool. So the following would end up
generating two fibers in the created pool:

```crystal
require "nested_scheduler"

NestedScheduler::ThreadPool.nursery do |pool|
  pool.spawn { spawn { sleep 5 } }
end
```

WARNING: `nested_scheduler` replaces the built in scheduler with
itself, which means that PROGRAMS THAT SPAWN FIBERS WILL NOT EXIT
UNTIL ALL FIBERS HAVE STOPPED RUNNING. This is in general a very good
thing, but it may be disruptive for programs not built assuming that.

### Threads
Nested Scheduler defaults to spawning a single thread to process
fibers, but it supports spawning more. To create a nursery with
multiple worker threads, instantiate it like

```crystal
require "nested_scheduler"

NestedScheduler::ThreadPool.nursery(thread_count: 4) do |pool|
  pool.spawn { .. }
end
```

The root nursery (that replaces the builtin scheduler at upstart) is
instantiated with 4 threads, just as the original.

Since `nested_scheduler` will create a pool of new threads, it is
possible to use it to spawn many threads and use it as a poor mans
replacement for asynchronous file IO. Doing blocking file IO in the
pool while continuing execution in the root pool is totally possible.

### (Experimental) Exceptions

The first exception raised will by bubble up the pool hiearchy.

Assume the following code:

```crystal
require "nested_scheduler"

NestedScheduler::ThreadPool.nursery do |pool|
  pool.spawn { raise "Err" }
end
```

What will happen here is that the pool will catch the error and then
re-raise the exception in the outerlying scope. No more silent
exceptions in fibers (unless you want them. People rarely do). Only
the first exception is kept.

### (Experimental) Result collection

By default only errors are kept track of. Something else that is
common is to want to keep the results of the execution.

That can be done using the following:

```crystal
require "nested_scheduler"

values = NestedScheduler::ThreadPool.collect(Int32) do |pool|
  pool.spawn { 4711 }
  pool.spawn { 13 }
end
values.sort!
```

After executing `values` will have the value `[13, 4711]`. If there is
an exception, or if one of the spawned fibers return something that is
of an incorrect type then there will be an exception raised from the
`collect` block.

### Cancelation

Currently only cooperative cancellation of a pool is supported. Example:

```crystal
  count = 0
  NestedScheduler::ThreadPool.nursery do |pl|
    pl.spawn do
      sleep 0.01
      pl.cancel
    end
    pl.spawn do
      loop do
        break if pl.canceled?
        count += 1
        sleep 0.001
      end
    end
  end
  # count will be > 7 when this point is reached.
```

Not supported are things like limited noncooperative canceling or
canceling of independent fibers without the surrounding pool.

## Future work

Eventually it would be nice to have more stream lined ways of creating
nurseries, but as long as creating one always will create at least one
dedicated new thread to process the work, it hasn't been necessary. It
will be more relevant once there are cheaper ways to create nurseries
that work gracefully within the current thread pool instead of having
to create at least one new thread for every nursery.

Also, cancelation, timeouts and perhaps grace periods needs a lot more
thought and work.

## Development

TODO: Write development instructions here

## Contributing

1. Fork it (<https://github.com/yxhuvud/nested_scheduler/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Linus Sellberg](https://github.com/yxhuvud) - creator and maintainer
