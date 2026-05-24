# frozen_string_literal: true

require "bundler/gem_tasks"

# The `spec` and `lint` tasks become real as later M0 issues land:
#   - #2 wires :lint to RuboCop::RakeTask
#   - #4 wires :spec to RSpec::Core::RakeTask
# Until then, these placeholders keep `rake` runnable on a fresh checkout.

begin
  require "rspec/core/rake_task"
  RSpec::Core::RakeTask.new(:spec)
rescue LoadError
  desc "Run the test suite (placeholder until #4 wires RSpec)"
  task :spec do
    puts "[spec] RSpec is not installed yet — skipping. Wired up in issue #4."
  end
end

begin
  require "rubocop/rake_task"
  RuboCop::RakeTask.new(:lint)
rescue LoadError
  desc "Run the linter (placeholder until #2 wires RuboCop)"
  task :lint do
    puts "[lint] RuboCop is not installed yet — skipping. Wired up in issue #2."
  end
end

task default: %i[spec lint]
