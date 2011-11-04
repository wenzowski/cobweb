# -*- encoding: utf-8 -*-
$:.push File.expand_path('../lib', __FILE__)
require 'cobweb/version'

spec = Gem::Specification.new do |s|
  s.name              = 'cobweb'
  s.version           = Cobweb::VERSION
  s.authors           = ['Stewart McKee', 'Alexander Wenzowski']
  s.email             = ['stewart@rockwellcottage.com', 'alexander@wenzowski.com']
  s.homepage          = 'http://github.com/wenzowski/cobweb'
  s.summary           = 'Crawler utilizing resque'
  # s.description     = %q{TODO: Write a gem description}

  s.files         = `git ls-files`.split('\n')
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split('\n')
  s.executables   = `git ls-files -- bin/*`.split('\n').map{ |f| File.basename(f) }
  s.require_paths = ['lib']

  s.extra_rdoc_files  = ['README.textile']

  s.add_runtime_dependency 'resque'
  s.add_runtime_dependency 'redis'
  s.add_runtime_dependency 'absolutize'
  s.add_runtime_dependency 'nokogiri'
  s.add_runtime_dependency 'addressable'
  s.add_runtime_dependency 'rake'  # pursuant to Rakefile `require 'resque/tasks'`
  s.add_runtime_dependency 'ap'    # AW: I think this is being used to render crawl statistics
  s.add_runtime_dependency 'crack' # AW: an undeclared dependency of 'ap'

  s.add_development_dependency 'bundler'
  s.add_development_dependency 'rspec'
  s.add_development_dependency 'guard'
  s.add_development_dependency 'guard-rspec'

  s.add_development_dependency 'rb-inotify' if RUBY_PLATFORM.downcase.include?('linux')
  s.add_development_dependency 'rb-fsevent' if RUBY_PLATFORM.downcase.include?('darwin')
  s.add_development_dependency 'growl_notify' if RUBY_PLATFORM.downcase.include?('darwin')
end
