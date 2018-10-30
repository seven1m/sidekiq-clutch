class Job1
  include Sidekiq::Worker
  include Sidekiq::Clutch::Worker

  def perform(x)
    log_job "#{self.class.name}#perform was called with #{x.inspect}"
    'result from Job1'
  end
end

class Job2
  include Sidekiq::Worker
  include Sidekiq::Clutch::Worker

  sidekiq_options queue: 'low'

  def perform(x, y)
    log_job "#{self.class.name}#perform was called with #{[x, y].inspect} and result #{previous_results.inspect}"
    'result from Job2'
  end
end

class Job3
  include Sidekiq::Worker
  include Sidekiq::Clutch::Worker

  def perform(x, y, z)
    log_job "#{self.class.name}#perform was called with #{[x, y, z].inspect} and result #{previous_results.inspect}"
    'result from Job3'
  end
end

class NestedJob
  include Sidekiq::Worker
  include Sidekiq::Clutch::Worker

  def perform
    log_job "#{self.class.name}#perform was called"
    clutch = Sidekiq::Clutch.new(batch)
    clutch.jobs << [Job1, 10]
    clutch.parallel do
      clutch.jobs << [Job2, 10, 'ten']
      clutch.jobs << [Job2, 10, 'ten']
    end
    clutch.engage
    'result from NestedJob'
  end
end

class FailingJob
  include Sidekiq::Worker
  include Sidekiq::Clutch::Worker

  def perform
    raise 'this job never succeeds'
  end
end

class FailureHandlerJob
  include Sidekiq::Worker
  include Sidekiq::Clutch::Worker

  def perform(status)
    log_job "#{self.class.name}#perform was called with #{status.inspect}"
  end
end
