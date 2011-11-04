source :rubygems

gemspec

group :development, :guard do
  gem 'guard'
  gem 'guard-rspec'
  gem 'rb-inotify' if RUBY_PLATFORM.downcase.include?('linux')
  gem 'rb-fsevent' if RUBY_PLATFORM.downcase.include?('darwin')
  gem 'growl_notify' if RUBY_PLATFORM.downcase.include?('darwin')
end