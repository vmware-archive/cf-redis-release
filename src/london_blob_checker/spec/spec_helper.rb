ROOT = File.dirname(__dir__)
$LOAD_PATH.unshift(File.expand_path('lib/london_blob_checker', ROOT))

require 'rspec/its'

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.filter_run :focus => true
  config.run_all_when_everything_filtered = true

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
end
