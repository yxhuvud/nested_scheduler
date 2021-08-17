# nested_scheduler

Nested Scheduler is an expansion and/or replacement for the built in
fiber scheduler of Crystal. It allows setting up thread pools with one
or more dedicated threads that will handle a set of fibers. It draws
inspiration from [Structured Concurrency](https://vorpus.org/blog/notes-on-structured-concurrency-or-go-statement-considered-harmful/).

## Installation

Step 1 is only needed if the uring context will be used.

TODO: Break it out to a library of its own for the uring context.

1. Have kernel 5.11+ installed.

2. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     nested_scheduler:
       github: yxhuvud/nested_scheduler
   ```

4. Run `shards install`

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

### Cancelation

Currently only cooperative cancellation is supported. Example:

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

## Future work

Eventually it would be nice to have more stream lined ways of creating
nurseries, but as long as creating one always will create at least one
dedicated new thread to process the work, it hasn't been necessary. It
will be more relevant once there are cheaper ways to create nurseries
that work gracefully within the current thread pool instead of having
to create at least one new thread for every nursery.

Oh, and the uring scheduler is very much experimental and not
currently documented. Expect things to be broken. Given that it has
the potential to allow asynchronous file IO, it is very much something
that is desireable in the long run though. Any help improving it is
welcome but don't expect it to work well (yet) :).

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
