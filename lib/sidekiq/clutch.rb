require 'sidekiq'
require 'sidekiq/clutch/version'
require 'sidekiq/clutch/worker'
require 'sidekiq/clutch/jobs_collection'
require 'sidekiq/clutch/job_wrapper'

module Sidekiq
  class Clutch
    # 22 days - how long a Sidekiq job can live with exponential backoff
    TEMPORARY_KEY_EXPIRATION_DURATION = 22 * 24 * 60 * 60

    def initialize(batch = nil)
      @batch = batch || Sidekiq::Batch.new
    end

    attr_reader :batch, :queue, :parallel_key

    attr_accessor :current_result_key, :on_failure

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
      set_jobs_data_in_redis(jobs_queue)
      return if step.nil?
      batch.callback_queue = queue if queue
      batch.on(:success, Sidekiq::Clutch, 'key_base' => key_base, 'result_key_index' => result_key_index(step))
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
      return on_success_legacy(status, options) if options['jobs']

      raise 'invariant: key_base is missing!' unless options['key_base']
      raise 'invariant: result_key_index is missing!' unless options['result_key_index']

      # NOTE: This is a brand new instance of Sidekiq::Clutch that Sidekiq instantiates,
      # so we need to set @key_base again.
      @key_base = options['key_base']
      remaining_jobs = JSON.parse(Sidekiq.redis { |r| r.get(jobs_key) })
      if remaining_jobs.empty?
        clean_up_temporary_keys
        return
      end
      parent_batch = Sidekiq::Batch.new(status.parent_bid)
      service = self.class.new(parent_batch)
      service.jobs.raw = remaining_jobs
      service.current_result_key = "#{key_base}-#{options['result_key_index']}"
      service.engage
    end

    def on_complete(status, options)
      return if status.failures.zero?
      return if options['on_failure'].nil?
      Object.const_get(options['on_failure']).new.perform(status)
    end

    private

    # accept old style of passing job data, will be removed in 3.0
    def on_success_legacy(status, options)
      @key_base = options['result_key'].sub(/-\d+$/, '')
      if options['jobs'].empty?
        clean_up_result_keys
        return
      end
      parent_batch = Sidekiq::Batch.new(status.parent_bid)
      service = self.class.new(parent_batch)
      service.jobs.raw = options['jobs']
      service.current_result_key = options['result_key']
      service.engage
    end

    def key_base
      @key_base ||= SecureRandom.uuid
    end

    def jobs_key
      "#{key_base}-jobs"
    end

    def set_jobs_data_in_redis(data)
      Sidekiq.redis do |redis|
        redis.multi do |multi|
          multi.set(jobs_key, data.to_json)
          multi.expire(jobs_key, TEMPORARY_KEY_EXPIRATION_DURATION)
        end
      end
    end

    def series_step(step)
      (klass, params) = step['series']
      enqueue_job(klass, params, result_key_index(step))
    end

    def parallel_step(step)
      step['parallel'].each do |(klass, params)|
        enqueue_job(klass, params, result_key_index(step))
      end
    end

    def result_key_index(step)
      if step['result_key_index']
        step['result_key_index']
      elsif step['result_key'] # legacy style, will be removed in 3.0
        step['result_key'].split('-').last.to_i
      else
        raise "invariant: expected result_key_index passed in step; got: #{step.inspect}"
      end
    end

    def enqueue_job(klass, params, result_key_index)
      job_options = Object.const_get(klass).sidekiq_options
      result_key = "#{key_base}-#{result_key_index}"
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

    def clean_up_temporary_keys
      Sidekiq.redis do |redis|
        redis.del(jobs_key)
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
