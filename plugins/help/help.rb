# Gems
require 'rubygems'
require 'bundler/setup'
# Gemfile gems
require 'ffi-rzmq'
require 'json'

require_relative '../plugin_framework.rb'

class Help < PluginFramework
  
  def command( location, from, cmd, param )
    puts "Help::command>" + [ location, from, cmd, param ].to_s
    if cmd == "help"
      if param.nil?
        # all modules
        # help:module location
        ignore = send_request "BOT:PRIVMSG", location + " Listing modules:"
        ignore = send_request "BOT:QUERY", "help:module #{location}"
      else
        # a specific module
        # help:module location module
        ignore = send_request "BOT:PRIVMSG", location + " Help for module #{param}:"
        ignore = send_request "BOT:QUERY", "help:module #{location} #{param}"
      end
    end
  end

end

help = Help.new "help", ARGV[0], ARGV[1]

help.describe "This module (gets help information)"
help.help_topic "help [module]", "Lists modules, or optionally help from a specific module"
help.respond_to_help true

begin
  help.subscribe_to "PRIVMSG"
  help.subscribe_to "NOTICE"

  help.run

rescue ZMQ::ContextError => e
  p e.inspect

rescue SystemExit, Interrupt
  # probably ctrl-c, this is okay :)

ensure
  help.cleanup

end