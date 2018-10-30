lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'sidekiq/clutch/version'

Gem::Specification.new do |spec|
  spec.name          = 'sidekiq-clutch'
  spec.version       = Sidekiq::Clutch::VERSION
  spec.authors       = ['Tim Morgan']
  spec.email         = ['tim@timmorgan.org']

  spec.summary       = 'An ergonomic wrapper API for Sidekiq Batches'
  spec.description   = 'Sidekiq::Clutch provides an ergonomic wrapper API for Sidekiq Batches ' \
                       'so you can easily manage serial and parallel jobs.'
  spec.homepage      = 'https://github.com/seven1m/sidekiq-clutch'
  spec.license       = 'MIT'

  spec.files         = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files`.split("\n").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.require_paths = ['lib']

  spec.add_dependency 'sidekiq', '>= 5.0.0'

  spec.add_development_dependency 'pry'
  spec.add_development_dependency 'bundler', '~> 1.16'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
end
