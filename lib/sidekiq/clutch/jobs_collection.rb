module Sidekiq
  class Clutch
    class JobsCollection
      def initialize(service)
        @service = service
        @jobs = []
        @result_key_prefix = SecureRandom.uuid
        @result_key_index = 0
      end

      def empty?
        @jobs.empty?
      end

      def raw
        @jobs
      end

      def raw=(jobs)
        @jobs = jobs
      end

      def <<((klass, *params))
        if @service.parallel?
          @jobs << new_parallel_step unless continue_existing_parallel_step?
          @jobs.last['parallel'] << [klass.name, params]
        else
          @jobs << { 'series' => [klass.name, params], 'result_key' => next_result_key }
        end
      end

      def next_result_key
        @result_key_index += 1
        "#{@result_key_prefix}-#{@result_key_index}"
      end

      private

      def new_parallel_step
        { 'parallel' => [], 'result_key' => next_result_key, 'parallel_key' => @service.parallel_key }
      end

      def continue_existing_parallel_step?
        @jobs.last && @jobs.last['parallel_key'] == @service.parallel_key
      end
    end
  end
end
