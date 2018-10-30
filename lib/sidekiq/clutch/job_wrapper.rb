module Sidekiq
  class Clutch
    class JobWrapper
      include Sidekiq::Worker

      def perform(bid, job_class, args, last_result_key, current_result_key)
        job = Object.const_get(job_class).new
        job.previous_results = Sidekiq.redis { |c| c.lrange(last_result_key, 0, -1) }.map do |r|
          JSON.parse(r, quirks_mode: true) # quirks_mode allows a bare string or number
        end
        job.define_singleton_method(:batch) { Sidekiq::Batch.new(bid) }
        result = job.perform(*args)
        Sidekiq.redis do |redis|
          redis.multi do |multi|
            multi.rpush(current_result_key, result.to_json)
            multi.expire(current_result_key, RESULT_KEY_EXPIRATION_DURATION)
          end
        end
      end
    end
  end
end
