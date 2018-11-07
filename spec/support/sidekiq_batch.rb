require 'securerandom'

# This is a really hacky fake Sidekiq::Batch class. It works _just enough_ to get the specs to pass. Don't hate me.
module Sidekiq
  class Batch
    class << self
      attr_accessor :batches
    end

    def initialize(bid = nil)
      if bid
        @bid = bid
        @callbacks = self.class.batches[@bid].callbacks
      else
        @bid = SecureRandom.uuid
        @callbacks = []
        self.class.batches ||= {}
        self.class.batches[@bid] = self
      end
    end

    attr_reader :bid, :callbacks
    attr_accessor :callback_queue

    def jobs
      yield
    end

    def mutable?
      true
    end

    def on(event, klass, options)
      @callbacks.unshift [event, klass, options]
    end

    def self.run_callbacks(failures = 0)
      batches.values.each do |batch|
        size = batch.callbacks.size
        size.times do
          (event, klass, options) = batch.callbacks.shift
          CallbackWrapper.perform_async(event, klass, options, failures)
        end
      end
    end

    def self.drain_all_and_run_callbacks
      until Sidekiq::Worker.jobs.size.zero? && batches.values.flat_map(&:callbacks).empty?
        begin
          Sidekiq::Worker.drain_all
        rescue StandardError => e
          raise unless e.message == 'this job never succeeds'
          Sidekiq::Worker.jobs.clear
          Sidekiq::Batch.run_callbacks(1)
        else
          Sidekiq::Batch.run_callbacks(0)
        end
      end
    end

    class CallbackWrapper
      include Sidekiq::Worker

      def perform(event, klass, options, failures)
        status = Status.new(failures)
        return if event == 'success' && failures.positive?
        Object.const_get(klass).new.send("on_#{event}", status, options)
      end
    end

    class Status
      def initialize(failures)
        @failures = failures
      end

      attr_reader :failures

      def parent_bid
        Sidekiq::Batch.batches.keys.last # totally faking it
      end
    end
  end
end
