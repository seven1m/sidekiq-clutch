require 'pp'
require 'sidekiq/testing'

RSpec.describe Sidekiq::Clutch do
  let(:batch_double) { double('Sidekiq::Batch') }

  before do
    Sidekiq.redis { |c| c.del('spec_results') }
  end

  it 'enqueues jobs in order, passing results along to the next set each time' do
    subject.jobs << [FakeJob1, 1]
    subject.parallel do
      subject.jobs << [FakeJob2, 2, 'two']
      subject.jobs << [FakeJob2, 22, 222]
    end
    subject.jobs << [FakeJob3, 3, 4, 5]
    subject.engage
    Sidekiq::Batch.drain_all_and_run_callbacks
    results = Sidekiq.redis { |c| c.lrange('spec_results', 0, -1) }
    expect(results).to eq(
      [
        'FakeJob1#perform was called with 1',
        'FakeJob2#perform was called with [2, "two"] and result ["result from FakeJob1"]',
        'FakeJob2#perform was called with [22, 222] and result ["result from FakeJob1"]',
        'FakeJob3#perform was called with [3, 4, 5] and result ["result from FakeJob2", "result from FakeJob2"]'
      ]
    )
  end

  it 'can nest itself' do
    subject.jobs << [FakeJob1, 1]
    subject.parallel do
      subject.jobs << [FakeJob2, 2, 'two']
      subject.jobs << [FakeNestedJob]
    end
    subject.jobs << [FakeJob3, 3, 4, 5]
    subject.engage
    Sidekiq::Batch.drain_all_and_run_callbacks
    results = Sidekiq.redis { |c| c.lrange('spec_results', 0, -1) }
    expect(results).to eq(
      [
        'FakeJob1#perform was called with 1',
        'FakeJob2#perform was called with [2, "two"] and result ["result from FakeJob1"]',
        'FakeNestedJob#perform was called',
        'FakeJob1#perform was called with 10',
        'FakeJob2#perform was called with [10, "ten"] and result ["result from FakeJob1"]',
        'FakeJob2#perform was called with [10, "ten"] and result ["result from FakeJob1"]',
        'FakeJob3#perform was called with [3, 4, 5] and result ["result from FakeJob2", "result from FakeNestedJob"]'
      ]
    )
  end

  it 'accepts a bare job class with no args' do
    subject.jobs << FakeNestedJob
    subject.engage
    Sidekiq::Batch.drain_all_and_run_callbacks
    results = Sidekiq.redis { |c| c.lrange('spec_results', 0, -1) }
    expect(results).not_to be_empty
  end

  it 'cleans up result keys' do
    subject.jobs << [FakeJob1, 1]
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
    subject.jobs << [FakeJob1, 1]
    subject.engage
    expect(Sidekiq::Worker.jobs.first).to include(
      'class' => 'Sidekiq::Clutch::JobWrapper',
      'queue' => 'critical'
    )
    Sidekiq::Batch.drain_all_and_run_callbacks
    subject.clear
    subject.parallel do
      subject.jobs << [FakeJob2, 1, 2]
    end
    subject.engage
    expect(Sidekiq::Worker.jobs.first).to include(
      'class' => 'Sidekiq::Clutch::JobWrapper',
      'queue' => 'critical'
    )
  end
end
