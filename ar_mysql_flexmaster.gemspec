# -*- encoding: utf-8 -*-
require File.expand_path('../lib/ar_mysql_flexmaster/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Ben Osheroff"]
  gem.email         = ["ben@zendesk.com"]
  gem.description   = %q{TODO: Write a gem description}
  gem.summary       = %q{TODO: Write a gem summary}
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "ar_mysql_flexmaster"
  gem.require_paths = ["lib"]
  gem.version       = ArMysqlFlexmaster::VERSION

  gem.add_runtime_dependency("mysql2")
  gem.add_runtime_dependency("activerecord")
  gem.add_development_dependency("appraisal")
end
