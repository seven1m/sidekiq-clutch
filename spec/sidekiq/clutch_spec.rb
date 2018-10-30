require 'pp'
require 'sidekiq/testing'

RSpec.describe Sidekiq::Clutch do
  let(:batch_double) { double('Sidekiq::Batch') }

  before do
    Sidekiq.redis { |c| c.del('log_results') }
  end

  def log_results
    Sidekiq.redis { |c| c.lrange('log_results', 0, -1) }
  end

  it 'enqueues jobs in order, passing results along to the next set each time' do
    subject.jobs << [Job1, 1]
    subject.parallel do
      subject.jobs << [Job2, 2, 'two']
      subject.jobs << [Job2, 22, 222]
    end
    subject.jobs << [Job3, 3, 4, 5]
    subject.engage
    Sidekiq::Batch.drain_all_and_run_callbacks
    expect(log_results).to eq(
      [
        'Job1#perform was called with 1',
        'Job2#perform was called with [2, "two"] and result ["result from Job1"]',
        'Job2#perform was called with [22, 222] and result ["result from Job1"]',
        'Job3#perform was called with [3, 4, 5] and result ["result from Job2", "result from Job2"]'
      ]
    )
  end

  it 'can nest itself' do
    subject.jobs << [Job1, 1]
    subject.parallel do
      subject.jobs << [Job2, 2, 'two']
      subject.jobs << [NestedJob]
    end
    subject.jobs << [Job3, 3, 4, 5]
    subject.engage
    Sidekiq::Batch.drain_all_and_run_callbacks
    expect(log_results).to eq(
      [
        'Job1#perform was called with 1',
        'Job2#perform was called with [2, "two"] and result ["result from Job1"]',
        'NestedJob#perform was called',
        'Job1#perform was called with 10',
        'Job2#perform was called with [10, "ten"] and result ["result from Job1"]',
        'Job2#perform was called with [10, "ten"] and result ["result from Job1"]',
        'Job3#perform was called with [3, 4, 5] and result ["result from Job2", "result from NestedJob"]'
      ]
    )
  end

  it 'accepts a bare job class with no args' do
    subject.jobs << NestedJob
    subject.engage
    Sidekiq::Batch.drain_all_and_run_callbacks
    expect(log_results).not_to be_empty
  end

  it 'cleans up result keys' do
    subject.jobs << [Job1, 1]
    subject.engage
    Sidekiq::Batch.drain_all_and_run_callbacks
    keys = subject.jobs.raw.map { |j| j['result_key'] }
    keys.map do |key|
      expect(Sidekiq.redis { |c| c.exists(key) }).to eq(false), "#{key} exists"
    end
  end

  it 'does nothing if no jobs are specified' do
    subject.queue = 'critical'
    expect { subject.engage }.not_to raise_error
    expect(Sidekiq::Worker.jobs).to be_empty
  end

  it 'can push to any queue' do
    expect_any_instance_of(Sidekiq::Batch).to receive(:callback_queue=).with('critical').at_least(:once)
    subject.queue = :critical
    subject.jobs << [Job1, 1]
    subject.engage
    expect(Sidekiq::Worker.jobs.first).to include(
      'class' => 'Sidekiq::Clutch::JobWrapper',
      'queue' => 'critical'
    )
    Sidekiq::Batch.drain_all_and_run_callbacks
    subject.clear
    subject.parallel do
      subject.jobs << [Job2, 1, 2]
    end
    subject.engage
    expect(Sidekiq::Worker.jobs.first).to include(
      'class' => 'Sidekiq::Clutch::JobWrapper',
      'queue' => 'critical'
    )
    Sidekiq::Batch.drain_all_and_run_callbacks
  end

  it 'does not always override job class queue' do
    subject.jobs << [Job2, 1, 2]
    subject.engage
    expect(Sidekiq::Worker.jobs.first).to include(
      'class' => 'Sidekiq::Clutch::JobWrapper',
      'queue' => 'low'
    )
    Sidekiq::Batch.drain_all_and_run_callbacks
    subject.clear
    subject.parallel do
      subject.jobs << [Job2, 1, 2]
    end
    subject.engage
    expect(Sidekiq::Worker.jobs.first).to include(
      'class' => 'Sidekiq::Clutch::JobWrapper',
      'queue' => 'low'
    )
    Sidekiq::Batch.drain_all_and_run_callbacks
  end

  it 'does not execute the next step in series if a job failed' do
    expect(Job1).not_to receive(:new)
    subject.jobs << FailingJob
    subject.jobs << Job1
    subject.engage
    Sidekiq::Batch.drain_all_and_run_callbacks
  end

  let(:failure_handler) { double('FailureHandlerJob') }

  it 'calls on_failure when a failure occurs' do
    expect(FailureHandlerJob).to receive(:new).and_return(failure_handler)
    expect(failure_handler).to receive(:perform).with(Sidekiq::Batch::Status)
    subject.on_failure = FailureHandlerJob
    subject.jobs << FailingJob
    subject.engage
    Sidekiq::Batch.drain_all_and_run_callbacks
  end

  it 'does not fail when calling a job without the Clutch::Worker mixin' do
    subject.jobs << JobWithoutMixin
    subject.engage
    expect { Sidekiq::Batch.drain_all_and_run_callbacks }.not_to raise_error
  end
end
