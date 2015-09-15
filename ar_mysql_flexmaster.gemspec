# -*- encoding: utf-8 -*-

Gem::Specification.new do |gem|
  gem.authors       = ["Ben Osheroff"]
  gem.email         = ["ben@zendesk.com"]
  gem.description   = %q{ar_mysql_flexmaster allows configuring N mysql servers in database.yml and auto-selects which is a master at runtime}
  gem.summary       = %q{select a master at runtime from a list}
  gem.homepage      = "http://github.com/osheroff/ar_mysql_flexmaster"

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "ar_mysql_flexmaster"
  gem.require_paths = ["lib"]
  gem.version       = "1.0.0"

  gem.add_runtime_dependency("mysql2")
  gem.add_runtime_dependency("activerecord")
  gem.add_runtime_dependency("activesupport")
  gem.add_development_dependency("rake")
  gem.add_development_dependency("wwtd")
  gem.add_development_dependency("minitest")
  gem.add_development_dependency("mocha", "~> 1.1.0")
  gem.add_development_dependency("bump")
  gem.add_development_dependency("pry")
  gem.add_development_dependency("mysql_isolated_server", "~> 0.5")
end
