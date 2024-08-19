module SQLite3

  VERSION = "1.6.8"

  module VersionProxy
    MAJOR = 1
    MINOR = 6
    TINY  = 8
    BUILD = nil

    STRING = [ MAJOR, MINOR, TINY, BUILD ].compact.join( "." )

    VERSION = ::SQLite3::VERSION
  end

  def self.const_missing(name)
    return super unless name == :Version
    warn(<<-eowarn) if $VERBOSE
#{caller[0]}: `SQLite::Version` will be removed in sqlite3-ruby version 2.0.0
    eowarn
    VersionProxy
  end
end
