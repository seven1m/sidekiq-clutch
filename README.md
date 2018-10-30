# Sidekiq::Clutch

**WARNING: This is alpha level software right now. I'm still testing this and may change the API at any point.**

Sidekiq::Clutch is the API I always wanted when working with Sidekiq Pro [Batches](https://github.com/mperham/sidekiq/wiki/Batches). So I built it!

Features:

* Add jobs to run in series or parallel or mix-and-match however you wish.
* Pass results from one job onto the next job in series.
* If running jobs in parallel, pass all the results to the following job in series.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'sidekiq-clutch'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install sidekiq-clutch

## Usage

Include the `Sidekiq::Clutch::Worker` mixin in your job class and write your `#perform` method as usual. For example:

```ruby
class MyJob1
  include Sidekiq::Worker
  include Sidekiq::Clutch::Worker

  def perform
    # do stuff
  end
end
```

Now, enqueue your jobs using a new `Sidekiq::Clutch` instance, like this:

```ruby
clutch = Sidekiq::Clutch.new
clutch.jobs << MyJob1
clutch.jobs << [MyJob2, 'arg1', 'arg2']
clutch.parallel do
  clutch.jobs << [MyJob3, 3]
  clutch.jobs << [MyJob3, 4]
  clutch.jobs << [MyJob3, 5]
end
clutch.jobs << MyFinalizerJob
clutch.engage
```

The jobs will run in this order:

* First, `MyJob1` will run.
* Second, `MyJob2` with args `'arg1'` and `'arg2'` will run.
* Third, in parallel, three jobs of `MyJob3`, each with args `3`, `4`, and `5` will run.
* Last, the `MyFinalizerJob` will run.

## Results from Prior Jobs

You can access the results from the previous job in the series using the `previous_results` method:

```ruby
class MyJob1
  include Sidekiq::Worker
  include Sidekiq::Clutch::Worker

  def perform
    'This string will be passed to the next job in the series'
  end
end

class MyJob2
  include Sidekiq::Worker
  include Sidekiq::Clutch::Worker

  def perform(arg1, arg2)
    puts "results of the previous job (MyJob1):"
    p previous_results # => ["This string will be passed to the next job in the series"]
  end
end
```

If the previous step in a series was a batch of parallel jobs, then `previous_results` will be an array
containing all the results from all the parallel jobs.

Some notes:
- Results are always in an array, even if there was only a single prior job run in series.
- Results are serialized as JSON and temporarily stored in Redis, so only return small-ish values.

## Handling Failure

When jobs fail, Sidekiq will retry them as usual. See [here](https://github.com/mperham/sidekiq/wiki/Error-Handling) for details on how Sidekiq handles job failure and retries.

Jobs next in a series will **not** be enqueued by Clutch as long as a prior job is failing.

If you wish to do something when a job in your batch fails, set `on_failure` like this:

```ruby
clutch = Sidekiq::Clutch.new
clutch.on_failure = MyFailureHandlerJob
# add jobs here...
clutch.engage
```

`MyFailureHandlerJob.new.perform(status)` will be called if one of the following scenarios occur:

1. A job in series fails.
2. One or more jobs in parallel fail and the rest complete.

Note: retries will continue to occur even after your failure handler job is called.

## Nested Batches

You can nest Clutch instances too!

```ruby
class MyNestedJob
  include Sidekiq::Worker
  include Sidekiq::Clutch::Worker

  def perform
    clutch = Sidekiq::Clutch.new(batch)
    clutch.jobs << [MyJob2, 'arg1', 'arg2']
    clutch.jobs << [MyJob3, 3]
    clutch.engage
    'result from MyNestedJob'
  end
end

clutch = Sidekiq::Clutch.new
clutch.jobs << MyJob1
clutch.jobs << MyNestedJob
clutch.jobs << MyFinalizerJob
clutch.engage
```

## Setting the Queue

You can set the queue for jobs (overriding any queue specified in the job class itself) and callbacks by setting it on Clutch, like this:

```ruby
clutch = Sidekiq::Clutch.new
clutch.queue = 'critical'
# add jobs here...
clutch.engage
```

## Note about the sidekiq-batch gem

I tested this with the third-party gem [sidekiq-batch](https://github.com/breamware/sidekiq-batch), which
purports to be a drop-in replacement for Sidekiq Pro batches. However, that gem seems to not support
[nested callbacks](https://github.com/breamware/sidekiq-batch/issues/11#issuecomment-330625800), which my gem
relies on. I'm sorry, this gem will **not** work with the sidekiq-batch gem -- it only works with sidekiq-pro.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
