require 'sidekiq'
require 'sidekiq/clutch/version'
require 'sidekiq/clutch/worker'
require 'sidekiq/clutch/jobs_collection'
require 'sidekiq/clutch/job_wrapper'

module Sidekiq
  class Clutch
    def initialize(batch = nil)
      @batch = batch || Sidekiq::Batch.new
      @queue = 'default'
    end

    attr_reader :batch

    attr_accessor :current_result_key, :queue

    def parallel
      @parallel = true
      yield
      @parallel = false
    end

    def parallel?
      @parallel == true
    end

    def jobs
      @jobs ||= JobsCollection.new(self)
    end

    def clear
      @jobs = nil
    end

    def engage
      jobs_queue = jobs.raw.dup
      step = jobs_queue.shift
      return if step.nil?
      batch.callback_queue = queue.to_s
      batch.on(:success, Sidekiq::Clutch, 'jobs' => jobs_queue.dup, 'result_key' => step['result_key'])
      batch.jobs do
        if step['series']
          enqueue_series_job(step)
        elsif step['parallel']
          enqueue_parallel_jobs(step)
        else
          raise "unknown step: #{step.inspect}"
        end
      end
    end

    def enqueue_series_job(step)
      (klass, params) = step['series']
      options = {
        'class' => JobWrapper,
        'queue' => queue.to_s,
        'args'  => [batch.bid, klass, params, current_result_key, step['result_key']]
      }
      Sidekiq::Client.push(options)
    end

    def enqueue_parallel_jobs(step)
      step['parallel'].each do |(klass, params)|
        options = {
          'class' => JobWrapper,
          'queue' => queue.to_s,
          'args'  => [batch.bid, klass, params, current_result_key, step['result_key']]
        }
        Sidekiq::Client.push(options)
      end
    end

    def on_success(_status, options)
      if options['jobs'].empty?
        clean_up_result_keys(options['result_key'].sub(/-\d+$/, ''))
        return
      end
      service = self.class.new(batch)
      service.jobs.raw = options['jobs']
      service.current_result_key = options['result_key']
      service.engage
    end

    def clean_up_result_keys(key_base)
      Sidekiq.redis do |redis|
        redis.keys(key_base + '*').each do |key|
          redis.del(key)
        end
      end
    end

    # 22 days - how long a Sidekiq job can live with exponential backoff
    RESULT_KEY_EXPIRATION_DURATION = 22 * 24 * 60 * 60
  end
end
