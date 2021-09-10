require 'sidekiq'
require 'sidekiq/clutch/version'
require 'sidekiq/clutch/worker'
require 'sidekiq/clutch/jobs_collection'
require 'sidekiq/clutch/job_wrapper'

module Sidekiq
  class Clutch
    # This is the maximum number of steps in the collection.
    # A serial job is one step and a set of parallel jobs is one step.
    # Sidekiq::Clutch is known to use insane amounts of Redis memory when too many
    # steps are added. This is an attempt to catch that problem during creation.
    DEFAULT_MAX_STEPS = 200

    class TooManySteps < StandardError; end

    def initialize(batch = nil, max_steps: DEFAULT_MAX_STEPS)
      @batch = batch || Sidekiq::Batch.new
      @max_steps = max_steps
    end

    attr_reader :batch, :queue, :parallel_key

    attr_accessor :current_result_key, :on_failure, :max_steps

    def parallel
      @parallel_key = SecureRandom.uuid
      yield
      @parallel_key = nil
    end

    def parallel?
      !!@parallel_key
    end

    def jobs
      @jobs ||= JobsCollection.new(self)
    end

    def clear
      @jobs = nil
    end

    def queue=(q)
      @queue = q && q.to_s
    end

    def engage
      return if jobs.empty?
      if batch.mutable?
        setup_batch
      else
        batch.jobs do
          @batch = Sidekiq::Batch.new
          setup_batch
        end
      end
    end

    def setup_batch
      jobs_queue = jobs.raw.dup
      step = jobs_queue.shift
      return if step.nil?
      batch.callback_queue = queue if queue
      batch.on(:success, Sidekiq::Clutch, 'jobs' => jobs_queue.dup, 'result_key' => step['result_key'])
      on_failure_name = on_failure&.name
      batch.on(:complete, Sidekiq::Clutch, 'on_failure' => on_failure_name) if on_failure_name
      batch.jobs do
        if step['series']
          series_step(step)
        elsif step['parallel']
          parallel_step(step)
        else
          raise "unknown step: #{step.inspect}"
        end
      end
    end

    def on_success(status, options)
      if options['jobs'].empty?
        clean_up_result_keys(options['result_key'].sub(/-\d+$/, ''))
        return
      end
      parent_batch = Sidekiq::Batch.new(status.parent_bid)
      service = self.class.new(parent_batch)
      service.jobs.raw = options['jobs']
      service.current_result_key = options['result_key']
      service.engage
    end

    def on_complete(status, options)
      return if status.failures.zero?
      return if options['on_failure'].nil?
      Object.const_get(options['on_failure']).new.perform(status)
    end

    private

    def series_step(step)
      (klass, params) = step['series']
      enqueue_job(klass, params, step['result_key'])
    end

    def parallel_step(step)
      step['parallel'].each do |(klass, params)|
        enqueue_job(klass, params, step['result_key'])
      end
    end

    def enqueue_job(klass, params, result_key)
      job_options = Object.const_get(klass).sidekiq_options
      options = {
        'class'     => JobWrapper,
        'queue'     => queue || job_options['queue'],
        'wrapped'   => klass,
        'args'      => [batch.bid, klass, params, current_result_key, result_key],
        'retry'     => job_options['retry'],
        'backtrace' => job_options['backtrace']
      }
      Sidekiq::Client.push(options)
    end

    def clean_up_result_keys(key_base)
      Sidekiq.redis do |redis|
        result_key_index = 1
        loop do
          result = redis.del("#{key_base}-#{result_key_index}")
          result_key_index += 1
          break if result == 0
        end
      end
    end
  end
end
