#!/usr/bin/env rake
require 'yaggy'
require 'rake/testtask'

Yaggy.gem(File.expand_path("ar_mysql_flexmaster.gemspec", File.dirname(__FILE__)), :push_gem => true)

Rake::TestTask.new(:test) do |test|
  test.libs << 'lib' << 'test'
  test.pattern = 'test/**/*_test.rb'
  test.verbose = true
end
