#!/usr/bin/env rake
require 'rake/testtask'

require 'appraisal'
require 'yaggy'

Yaggy.gem(File.expand_path("ar_mysql_flexmaster.gemspec", File.dirname(__FILE__)), :push_gem => true)

Rake::TestTask.new(:test_units) do |test|
  test.libs << 'lib' << 'test'
  test.pattern = 'test/*_test.rb'
  test.verbose = true
end

task :test do 
  retval = true
  retval &= Rake::Task[:test_units].invoke
  retval &= system(File.dirname(__FILE__) + "/test/integration/run_integration_tests")
end

task :default => :test
