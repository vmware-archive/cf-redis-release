source 'https://rubygems.org'

gem 'aws-sdk'
gem 'bosh_cli', '1.2858.0'
gem 'redis'
gem 'rake'

group :test do
  gem 'rspec', '~> 3.1.0'
  gem 'pry'

  gem 'hula', source: "https://gem.fury.io/me"
  gem 'prof', source: "https://gem.fury.io/me"
end if ENV['CI']
