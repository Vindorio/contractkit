# frozen_string_literal: true

require "bundler/gem_tasks"

require "rspec/core/rake_task"
RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"
RuboCop::RakeTask.new(:lint)

task default: %i[spec lint]

namespace :naics do
  desc "Regenerate NAICS 2022 full JSON from Census Bureau XLSX"
  task :seed do
    script = File.expand_path("script/regenerate_naics.py", __dir__)
    sh "python3", script
  end
end
