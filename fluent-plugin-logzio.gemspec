# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |s|
  s.name        = 'fluent-plugin-logzio'
  s.version     = '0.0.15'
  s.authors     = ['Yury Kotov', 'Roi Rav-Hon', 'Arcadiy Ivanov']
  s.email       = ['bairkan@gmail.com', 'roi@logz.io', 'arcadiy@ivanov.biz']
  s.homepage    = 'https://github.com/logzio/fluent-plugin-logzio'
  s.summary     = %q{Fluentd plugin for output to Logz.io}
  s.description = %q{Fluentd pluging (fluent.org) for output to Logz.io (logz.io)}
  s.license     = 'Apache-2.0'

  s.rubyforge_project = 'fluent-plugin-logzio'

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.require_paths = ['lib']
  s.required_ruby_version = Gem::Requirement.new('>= 2.1.0')

  s.add_dependency 'net-http-persistent', '~> 2.9'
  s.add_runtime_dependency 'fluentd', ['>= 0.14.0', '< 2']
  s.add_development_dependency 'rake', '~> 12.3'
  s.add_development_dependency 'bundler', '~> 1.16'
  s.add_development_dependency 'rspec', '~> 3.7'
  s.add_development_dependency 'test-unit', '~> 3.2'
end
