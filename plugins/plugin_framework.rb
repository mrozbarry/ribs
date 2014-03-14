# Gems
require 'rubygems'
require 'bundler/setup'
# Gemfile gems
require 'ffi-rzmq'
require 'json'

class PluginFramework

  def initialize( name, subscription_connection, request_connection )
    @name = name

    @description = ""
    @topics = {}

    @ctx = ZMQ::Context.create 1
    @subscribe = @ctx.socket ZMQ::SUB
    @request = @ctx.socket ZMQ::REQ

    @subscribe.connect subscription_connection
    # Always interested in the bot quitting
    @subscribe.setsockopt ZMQ::SUBSCRIBE, "BOT:QUIT"

    @request.connect request_connection

    @poll = ZMQ::Poller.new
    @poll.register_readable @subscribe
    @poll.register_writable @request

    @config = JSON.parse( send_request( "BOT:QUERY", "config" ) )
    @nick = send_request( "BOT:QUERY", "nick" )

    @keep_alive = true

    @next_ping = Time.now.to_i + 60
    
    @registered = true
    if "ok" != send_request( "PLUGIN:REGISTER", @name )
      @keep_alive = false
      @registered = false
    end
  end

  def describe( text )
    @description = text
  end

  def help_topic( topic, data )
    @topics[topic] = data
  end

  def respond_to_help( toggle )
    if toggle
      subscribe_to "BOT:HELP"
    else
      unsubscribe_from "BOT:HELP"
    end
  end

  def subscribe_to( prefix )
    @subscribe.setsockopt ZMQ::SUBSCRIBE, prefix.to_s
    puts "PluginFramework::subscribe_to>" + prefix
  end

  def unsubscribe_from( prefix )
    @subscribe.setsockopt ZMQ::UNSUBSCRIBE, prefix.to_s
    puts "PluginFramework::unsubscribe_from>" + prefix
  end

  def send_request( directive, data )
    puts "Request> " + directive.to_s + " -> " + data.to_s
    @request.send_string directive.to_s + " -> " + data.to_s
    msg = ""
    @request.recv_string msg, 0
    puts "Response>" + msg
    return msg
  end

  def cleanup
    ignore = send_request( "PLUGIN:UNREGISTER", @name ) if @registered
    @request.close
    @subscribe.close
    @ctx.terminate
  end

  def command( location, from, cmd, param )
    # overwrite me
  end

  def published( key, data )
    @keep_alive = false if key == "BOT:QUIT"
    # Default PRIVMSG/NOTICE handling (even if it's not explicitly needed)
    if ( key == "PRIVMSG" ) || ( key == "NOTICE" )
      ircmsg = JSON.parse( data )
      contents = ircmsg["args"][-1].split( " ", 2 )
      if contents[0][0] == @config["commands"]["short_prefix"].to_s
        command ircmsg.has_key?( "channel" ) ? ircmsg["channel"] : ircmsg["args"][0], ircmsg["sender"], contents[0][1..-1], contents[1]
      elsif (@config["commands"]["allow_nick_as_prefix"] == true) && contents[0].downcase.start_with?( @nick )
        contents = contents[1].split( " ", 2 )
        command ircmsg.has_key?( "channel" ) ? ircmsg["channel"] : ircmsg["args"][0], ircmsg["sender"], contents[0], contents[1]
      end
    elsif key == "BOT:HELP"
      info = data.split(" ")
      if (info.count == 2) && (info[1] == @name)
        @topics.each do |key,value|
          ignore = send_request "BOT:PRIVMSG", "#{info[0]} help: " + @config["commands"]["short_prefix"] + "#{key} - " + value
        end
        if @topics.count == 0
          ignore = send_request "BOT:PRIVMSG", "#{info[0]} #{@name} has no topics"
        end
      elsif info.count == 1
        ignore = send_request "BOT:PRIVMSG", "#{info[0]} Module `#{@name}` is loaded" + (@description.empty? ? "" : "; " + @description)
      end
    end
      

    #override if needed?
  end

  def run

    while @keep_alive do

      @poll.poll 500

      readable = @poll.readables
      if readable.count
        @poll.readables.each do |sock|
          msg = ""
          sock.recv_string msg, 0
          args = msg.split " -> ", 2
          published( args[0], args[1] )
        end
      end

      if Time.now.to_i >= @next_ping
        @keep_alive = false if "ok" != send_request( "PLUGIN:PING", @name )
        @next_ping = Time.now.to_i + 60
      end


    end

  end

end