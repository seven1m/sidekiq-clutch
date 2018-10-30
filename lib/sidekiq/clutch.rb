require 'sidekiq'
require 'sidekiq/clutch/version'
require 'sidekiq/clutch/worker'
require 'sidekiq/clutch/jobs_collection'
require 'sidekiq/clutch/job_wrapper'

module Sidekiq
  class Clutch
    def initialize(batch = nil)
      @batch = batch || Sidekiq::Batch.new
    end

    attr_reader :batch

    attr_accessor :current_result_key

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

    def engage
      jobs_queue = jobs.raw.dup
      step = jobs_queue.shift
      batch.on(:success, Sidekiq::Clutch, 'jobs' => jobs_queue.dup, 'result_key' => step['result_key'])
      batch.jobs do
        if (job = step['series'])
          (klass, params) = job
          perform_async(batch.bid, klass, params, step['result_key'])
        elsif (parallel_jobs = step['parallel'])
          parallel_jobs.each do |(klass, params)|
            perform_async(batch.bid, klass, params, step['result_key'])
          end
        else
          raise "unknown step: #{step.inspect}"
        end
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

    def perform_async(bid, job_class, params, result_key)
      JobWrapper.perform_async(bid, job_class, params, current_result_key, result_key)
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
