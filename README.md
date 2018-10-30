# Sidekiq::Clutch

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

## Results from Prior Jobs

You can access the results from a previous job in a series, or multiple jobs that ran in parallel, using the `previous_results` method:

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

Note: results are always in an array, even if there was only a single prior job run in series.

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

## Note about the sidekiq-batch gem

I tested this with the third-party gem [sidekiq-batch](https://github.com/breamware/sidekiq-batch), which
purports to be a drop-in replacement for Sidekiq Pro batches. However, that gem seems to not support
[nested callbacks](https://github.com/breamware/sidekiq-batch/issues/11#issuecomment-330625800), which my gem
relies on. I'm sorry, this gem will **not** work with the sidekiq-batch gem -- it only works with sidekiq-pro.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
