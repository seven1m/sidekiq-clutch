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

    attr_reader :batch, :queue

    attr_accessor :current_result_key, :on_failure

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

    def queue=(q)
      @queue = q && q.to_s
    end

    def engage
      jobs_queue = jobs.raw.dup
      step = jobs_queue.shift
      return if step.nil?
      batch.callback_queue = queue if queue
      batch.on(:success, Sidekiq::Clutch, 'jobs' => jobs_queue.dup, 'result_key' => step['result_key'])
      batch.on(:complete, Sidekiq::Clutch, 'on_failure' => on_failure&.name)
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
        'args'      => [batch.bid, klass, params, current_result_key, result_key],
        'retry'     => job_options['retry'],
        'backtrace' => job_options['backtrace']
      }
      Sidekiq::Client.push(options)
    end

    def clean_up_result_keys(key_base)
      Sidekiq.redis do |redis|
        redis.keys(key_base + '*').each do |key|
          redis.del(key)
        end
      end
    end
  end
end
