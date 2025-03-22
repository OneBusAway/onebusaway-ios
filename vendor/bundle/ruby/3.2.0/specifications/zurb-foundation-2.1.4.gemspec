# -*- encoding: utf-8 -*-
# stub: zurb-foundation 2.1.4 ruby lib

Gem::Specification.new do |s|
  s.name = "zurb-foundation".freeze
  s.version = "2.1.4"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["ZURB".freeze]
  s.date = "2011-12-19"
  s.description = "An easy to use, powerful, and flexible framework for building prototypes and production code on any kind of device.".freeze
  s.email = ["foundation@zurb.com".freeze]
  s.homepage = "http://foundation.zurb.com".freeze
  s.rubygems_version = "3.4.10".freeze
  s.summary = "Get up and running with Foundation in seconds".freeze

  s.installed_by_version = "3.4.10" if s.respond_to? :installed_by_version

  s.specification_version = 3

  s.add_runtime_dependency(%q<rails>.freeze, ["~> 3.1.0"])
  s.add_runtime_dependency(%q<jquery-rails>.freeze, ["~> 1.0"])
end
