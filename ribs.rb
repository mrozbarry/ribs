# Gems
require 'rubygems'
require 'bundler/setup'
# Gemfile gems
require 'ffi-rzmq'
require 'ircsupport'
require 'json'

# System gems
require 'socket'
require 'time'

# Custom rb files
require_relative 'context.rb'

# IRC Instance (one per run for now)

class IRCConnection
  def initialize( ribs_ctx, server, port = 6667, nick = "ribs" )
    @bytes_out = 1
    @tcp = TCPSocket.open( server.to_s, port )
    @ctx = ribs_ctx
    @desired_nick = nick
    @nick_attempts = 0
    @server_line_endings = "";
    @buffer = "";
    @plugins = {}
    begin
      json = File.read( "config/config.json" )
      @config = JSON.load json
    rescue JSON::ParserError => e
      @config = {}
      puts e.inspect
    end
    log "New instance started", "DEBUG"
    log "Connecting to " + server.to_s + ":" + port.to_s
    raw "user ribs-bot * * :Ruby RIBS bot"
    nick nick.to_s
  end

  def log( msg, type = "INFO" )
    puts "[" + type.to_s + "] " + Time.now.strftime( "%H:%M:%S" ) + "> " + msg.to_s
  end

  def raw( msg )
    @bytes_out = @tcp.send msg.to_s + "\r\n", 0
    return @bytes_out
  end

  def nick( new_nick, track = false )
    @nick_attempts = 0 if !track
    @nick_attempts += 1 if track
    @desired_nick = new_nick
    n = @desired_nick + (track ? @nick_attempts.to_s : "")
    raw "NICK " + n
    @nick = n
  end

  def handle_irc
    # check for socket reads
    flags = select( [@tcp], nil, nil, 0.1 )

    # If we got some
    if flags
      # Check our socket
      if flags[0][0] == @tcp
        @buffer += @tcp.recv_nonblock( 1 ).force_encoding("UTF-8")
      else
        @bytes = -1 # likely a connection error?
      end
    end
  end

  def process_message( msg )
    hash = {}
    msg.instance_variables.each{|var| hash[var.to_s.delete("@")] = msg.instance_variable_get(var)}
    @ctx.publish( msg.command, hash.to_json)
    if msg.command == "PING"
      log msg.args.to_s, msg.command
      raw "PONG :" + msg.args[-1]
    elsif msg.command == "001"
      @joins.each do |channel|
        raw "JOIN " + channel.to_s
      end
    elsif msg.command == "433"
      nick @desired_nick, true
    end
    #puts hash
  end

  def process_buffer
    ircmsg = IRCSupport::Parser.new
    if !@buffer.empty?
      if @server_line_endings.empty?
        if @buffer.count( "\r\n" ) > 0
          @server_line_endings = "\r\n"
        elsif @buffer.count( "\n" ) > 0
          @server_line_endings = "\n"
        end
      end
      return if @server_line_endings.empty?
      begin
        offset = @buffer.index( @server_line_endings )
        if ( !offset.nil? )
          offset += @server_line_endings.length
          piece = @buffer.slice!(0...offset)
          piece = piece.chomp( @server_line_endings )
          #p piece
          begin
            process_message ircmsg.parse( piece )
          rescue IRCSupport::ArgumentError => e
            log "Can't process irc message; " + e.inspect, "IRCSUPPORT"
          end
        end
      end while !offset.nil?
    end
  end

  def reply( data )
    log data, "PLUGIN/RESPONSE"
    @ctx.reply data
  end

  def has_plugin?( name )
    return false if !@plugins.has_key? name
    now = Time.now.to_i
    if @plugins[ name ] > 0
      if Time.now.to_i > @plugins[ name ]
        log "Expiring plugin '#{name}', expired at " + @plugins[name].to_s + ", it is now " + now.to_s, "PLUGIN/EXPIRY"
        @plugins.delete name
        return false
      end
    end
    return true
  end

  def plugin_unregister( name )
    return "fail" if !has_plugin? name
    @plugins.delete name
    return "ok"
  end

  def plugin_ping( name )
    return "fail" if !has_plugin? name
    @plugins[ name ] = Time.now.to_i + (60 * 5) # 5 minute lease
    return "ok"
  end

  def plugin_register( name )
    return "fail" if has_plugin? name
    @plugins.store name, 0
    plugin_ping name
    return "ok"
  end

  def process_query( type )
    if type == "nick"
      return @nick
    elsif type == "config"
      return JSON.generate( @config )
    elsif type.start_with? "help:module"
      chunks = type.split(" ")
      # BOT:HELP location [module]
      @ctx.publish "BOT:HELP", chunks[1] + ( chunks[2].nil? ? "" : " " + chunks[2] )
      return "ok"
    end
  end

  def plugin_request( type, data )
    log type + " -> " + data, "PLUGIN"

    if type == "PLUGIN:REGISTER"
      reply plugin_register( data )
    
    elsif type == "PLUGIN:UNREGISTER"
      reply plugin_unregister( data )
    
    elsif type == "PLUGIN:PING"
      reply plugin_ping( data )
    
    elsif type == "BOT:QUERY"
      reply process_query data
    
    elsif type == "BOT:PRIVMSG"
      pieces = data.split( " ", 2 )
      if pieces.count == 2
        raw "PRIVMSG " + pieces[0] + " :" + pieces[1]
        reply "ok"
      end
    
    elsif type == "BOT:JOIN"
      raw "JOIN #{data}"
      reply "ok"

    elsif type== "BOT:PART"
      part = data.split(" ", 2)
      raw "PART #{part[0]}" + (part[1].nil? ? "" : " :" + part[1] )
      reply "ok"

    end
  end

  def run( joins, recover )
    @joins = joins || []
    begin

      handle_irc
      process_buffer

      @ctx.process.each do |msg|
        plugin_request msg[0], msg[1]
      end

      #puts @bytes_out.to_s + "last bytes out"
    end while @bytes_out > 0
    run( joins, recover ) if recover
  end
end

ctx = Context.new
# Right now, we only want plugins running from the local machine
ctx.publish_bind( "tcp", "*", 8881 )
ctx.reply_bind( "tcp", "*", 8882 )

ribs = IRCConnection.new ctx, "irc.freenode.net"

begin

  ribs.run [ "#beardedbarry" ], false

rescue SystemExit, Interrupt
  #raise
rescue Exception => e
  # ... do nothing?
  puts e.inspect
  puts e.to_s
ensure
  ctx.publish "BOT:QUIT", "quit"
  ribs.raw "QUIT :bot closing"
end
