#!/usr/bin/env rake
require 'rake/testtask'

require 'bump/tasks'
require 'wwtd/tasks'

Rake::TestTask.new(:test_units) do |test|
  test.libs << 'lib' << 'test'
  test.pattern = 'test/*_test.rb'
  test.verbose = true
end

task :test do
  retval = true
  retval &= Rake::Task[:test_units].invoke
  retval &= system(File.dirname(__FILE__) + "/test/integration/run_integration_tests")
  exit retval
end

task :default => 'wwtd:local'
