# -*- encoding: utf-8 -*-
# stub: sqlite3 1.6.8 arm64-darwin lib

Gem::Specification.new do |s|
  s.name = "sqlite3".freeze
  s.version = "1.6.8"
  s.platform = "arm64-darwin".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "bug_tracker_uri" => "https://github.com/sparklemotion/sqlite3-ruby/issues", "changelog_uri" => "https://github.com/sparklemotion/sqlite3-ruby/blob/master/CHANGELOG.md", "documentation_uri" => "https://www.rubydoc.info/gems/sqlite3", "homepage_uri" => "https://github.com/sparklemotion/sqlite3-ruby", "rubygems_mfa_required" => "true", "source_code_uri" => "https://github.com/sparklemotion/sqlite3-ruby" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Jamis Buck".freeze, "Luis Lavena".freeze, "Aaron Patterson".freeze, "Mike Dalessio".freeze]
  s.date = "2023-11-01"
  s.description = "Ruby library to interface with the SQLite3 database engine (http://www.sqlite.org). Precompiled\nbinaries are available for common platforms for recent versions of Ruby.\n".freeze
  s.extra_rdoc_files = ["API_CHANGES.md".freeze, "CHANGELOG.md".freeze, "README.md".freeze, "ext/sqlite3/aggregator.c".freeze, "ext/sqlite3/backup.c".freeze, "ext/sqlite3/database.c".freeze, "ext/sqlite3/exception.c".freeze, "ext/sqlite3/sqlite3.c".freeze, "ext/sqlite3/statement.c".freeze]
  s.files = ["API_CHANGES.md".freeze, "CHANGELOG.md".freeze, "README.md".freeze, "ext/sqlite3/aggregator.c".freeze, "ext/sqlite3/backup.c".freeze, "ext/sqlite3/database.c".freeze, "ext/sqlite3/exception.c".freeze, "ext/sqlite3/sqlite3.c".freeze, "ext/sqlite3/statement.c".freeze]
  s.homepage = "https://github.com/sparklemotion/sqlite3-ruby".freeze
  s.licenses = ["BSD-3-Clause".freeze]
  s.rdoc_options = ["--main".freeze, "README.md".freeze]
  s.required_ruby_version = Gem::Requirement.new([">= 2.7".freeze, "< 3.3.dev".freeze])
  s.rubygems_version = "3.4.10".freeze
  s.summary = "Ruby library to interface with the SQLite3 database engine (http://www.sqlite.org).".freeze

  s.installed_by_version = "3.4.10" if s.respond_to? :installed_by_version
end
