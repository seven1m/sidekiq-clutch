module Sidekiq
  class Clutch
    module Worker
      def self.included(base)
        base.class_eval do
          attr_accessor :previous_results
        end
      end

      def perform(last_result_key, current_result_key, args)
        self.previous_results = Sidekiq.redis { |c| c.lrange(last_result_key, 0, -1) }.map do |r|
          JSON.parse(r, quirks_mode: true) # quirks_mode allows a bare string or number
        end
        result = perform!(*args)
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
