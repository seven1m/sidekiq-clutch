class FakeJob1
  include Sidekiq::Worker
  include Sidekiq::Clutch::Worker

  def perform(x)
    log_job "#{self.class.name}#perform was called with #{x.inspect}"
    'result from FakeJob1'
  end
end

class FakeJob2
  include Sidekiq::Worker
  include Sidekiq::Clutch::Worker

  def perform(x, y)
    log_job "#{self.class.name}#perform was called with #{[x, y].inspect} and result #{previous_results.inspect}"
    'result from FakeJob2'
  end
end

class FakeJob3
  include Sidekiq::Worker
  include Sidekiq::Clutch::Worker

  def perform(x, y, z)
    log_job "#{self.class.name}#perform was called with #{[x, y, z].inspect} and result #{previous_results.inspect}"
    'result from FakeJob3'
  end
end

class FakeNestedJob
  include Sidekiq::Worker
  include Sidekiq::Clutch::Worker

  def perform
    log_job "#{self.class.name}#perform was called"
    clutch = Sidekiq::Clutch.new(batch)
    clutch.jobs << [FakeJob1, 10]
    clutch.parallel do
      clutch.jobs << [FakeJob2, 10, 'ten']
      clutch.jobs << [FakeJob2, 10, 'ten']
    end
    clutch.engage
    'result from FakeNestedJob'
  end
end
