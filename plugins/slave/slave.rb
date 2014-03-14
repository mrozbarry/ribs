# Gems
require 'rubygems'
require 'bundler/setup'
# Gemfile gems
require 'ffi-rzmq'
require 'json'

require_relative '../plugin_framework.rb'

class Slave < PluginFramework
  
  def command( location, from, cmd, param )
    puts "Slave::command>" + [ location, from, cmd, param ].to_s
    if cmd == "join"
      ignore = send_request "BOT:JOIN", param
    
    elsif cmd == "part"
      ignore = send_request "BOT:PART", param

    end
  end

end

slave = Slave.new "slave", ARGV[0], ARGV[1]

slave.describe "Tell this bot where to go"
slave.help_topic "join <channel>", "Joins a channel"
slave.help_topic "part <channel> [reason]", "Parts a channel"
slave.respond_to_help true

begin
  slave.subscribe_to "PRIVMSG"
  slave.subscribe_to "NOTICE"

  slave.run

rescue ZMQ::ContextError => e
  p e.inspect

rescue SystemExit, Interrupt
  # probably ctrl-c, this is okay :)

ensure
  slave.cleanup

end