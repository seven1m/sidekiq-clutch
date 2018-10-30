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

    def jobs
      yield
    end

    def on(event, klass, options)
      @callbacks.unshift [event, klass, options]
    end

    def self.run_callbacks
      batches.values.each do |batch|
        size = batch.callbacks.size
        size.times do
          (event, klass, options) = batch.callbacks.shift
          CallbackWrapper.perform_async(event, klass, options)
        end
      end
    end

    def self.drain_all_and_run_callbacks
      until Sidekiq::Worker.jobs.size.zero? && batches.values.flat_map(&:callbacks).empty?
        Sidekiq::Worker.drain_all
        Sidekiq::Batch.run_callbacks
      end
    end

    class CallbackWrapper
      include Sidekiq::Worker

      def perform(event, klass, options)
        Object.const_get(klass).new.send("on_#{event}", event, options)
      end
    end
  end
end

