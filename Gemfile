source :rubygems

gemspec

group :development
  gem 'yajl-ruby', '~>0.8.2', :platforms => :mri # resque dependency not passed
end

group :development, :guard do
  gem 'guard'
  gem 'guard-rspec'
  gem 'rb-inotify' if RUBY_PLATFORM.downcase.include?('linux')
  gem 'rb-fsevent' if RUBY_PLATFORM.downcase.include?('darwin')
  gem 'growl_notify' if RUBY_PLATFORM.downcase.include?('darwin')
end