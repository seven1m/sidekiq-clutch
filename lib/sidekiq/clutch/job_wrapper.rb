module Sidekiq
  class Clutch
    class JobWrapper
      include Sidekiq::Worker

      def perform(bid, job_class, args, last_result_key, current_result_key)
        job = Object.const_get(job_class).new
        assign_previous_results(job, last_result_key)
        job.define_singleton_method(:batch) { Sidekiq::Batch.new(bid) }
        result = job.perform(*args)
        Sidekiq.redis do |redis|
          redis.multi do |multi|
            multi.rpush(current_result_key, result.to_json)
            multi.expire(current_result_key, TEMPORARY_KEY_EXPIRATION_DURATION)
          end
        end
      end

      private

      def lookup_last_result(key)
        Sidekiq.redis do |client|
          client.lrange(key, 0, -1)
        end
      end

      def assign_previous_results(job, last_result_key)
        return unless job.respond_to?(:previous_results=)
        return job.previous_results = [] if last_result_key.nil?
        job.previous_results = lookup_last_result(last_result_key).map do |r|
          JSON.parse(r, quirks_mode: true) # quirks_mode allows a bare string or number
        end
      end
    end
  end
end
