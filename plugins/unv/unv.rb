# Gems
require 'rubygems'
require 'bundler/setup'
# Gemfile gems
require 'ffi-rzmq'
require 'json'

# System gems
require 'socket'
require 'timeout'

# Plugin Framework
require_relative '../plugin_framework.rb'

class Q3 < PluginFramework

  def initialize( name, subscription_connection, request_connection )
    super

    @notifications = []
  end

  def query_server( server, port, type, timeout_sec, max_attempts = 5)
    return nil if max_attempts == 0
    socket = UDPSocket.new

    message = "xxxx" + type
    # Update to OOB header
    message[0] = "\xff"
    message[1] = "\xff"
    message[2] = "\xff"
    message[3] = "\xff"

    socket.send message, 0, server, port
    begin
      Timeout.timeout timeout_sec do
        data = socket.recvfrom 65507
        pieces = data[0].split( "\\" )
        return pieces
        player_data = pieces.last.split( "\n" )
        player_data.shift

        players = []
        player_data.each do |player|
          p = player.split(" ")
          puts p
          pl = {}
          pl["score"] = p[0].to_i
          pl["ping"] = p[1].to_i
          pl["name"] = player.gsub "\"",""
          players << pl
        end

        pieces.shift
        vars["players"] = players
        return vars
      end
    rescue Timeout::Error => e
      return query_server server, port, type, timeout_sec, max_attempts - 1
    end
  end

  def parseKeyValue( kv )
    #kv.shift if shift_first
    vars = {}
    kv.each_with_index do |d, i|
      vars[d] = kv[i+1] if (i % 2) == 0
    end
    return vars
  end

  def query_status( server, port, timeout_sec, max_attempts = 5 )
    data = query_server server, port, "getstatus", timeout_sec, max_attempts
    chunks = data.last.split( "\n" )
    data.shift
    kv = data
    players = chunks

    connected = []
    players.each do |player|
      puts "player: #{player}"
      p = player.split " "
      score = p.shift.to_i
      ping = p.shift.to_i
      p = p.join " "
      name = p.gsub "\"", ""
      plyr = { :score => score, :ping => ping, :name => name }
      puts plyr
      connected << plyr
    end

    return [ parseKeyValue( kv ), connected ]

  end
  
  def command( location, from, cmd, param )
    puts "Unv::command>" + [ location, from, cmd, param ].to_s
    if cmd == "unv"
      p = param.split( " " )
      subcmd = p[0]
      params = p[1...-1]

      if subcmd == "info"
        meta = query_server( params[0], params[1].nil? ? 27960 : params[1].to_i, "getinfo", 10, 3)
        meta.shift
        data = parseKeyValue meta
        ignore = send_request "BOT:PRIVMSG", "#{location} #{data['hostname']} has #{data['clients']} of #{data['sv_maxclients']} players (and #{data['bots']} bots)"
        ignore = send_request "BOT:PRIVMSG", "#{location} #{data['hostname']} on map #{data['mapname']}"

      elsif subcmd == "status"
        processed = query_status params[0], params[1].nil? ? 27960 : params[1].to_i, 10, 3

        status = processed.first
        players = processed.last

        #puts status

        ignore = send_request "BOT:PRIVMSG", "#{location} #{status['sv_hostname']} is running #{status['version']}"
        passprotected = "is not"
        passprotected = "is" if status["g_need_pass"].to_i != 0
        ignore = send_request "BOT:PRIVMSG", "#{location} #{status['sv_hostname']} #{passprotected} password protected"
        ignore = send_request "BOT:PRIVMSG", "#{location} #{status['sv_hostname']} is using map #{status['mapname']}"
        player_list = []
        players.each do |player|
          player_list << player[:name]
        end
        ignore = send_request "BOT:PRIVMSG", "#{location} #{status['sv_hostname']} players:" + player_list.join( ", ")
      elsif subcmd == "notify"
        @notifications << {
          :notify => params[0],
          :at_least_x_players => params[1].to_i,
          :host => params[2],
          :port => params[3].nil? ? 27960 : params[3].to_i,
          :next_check => Time.now.to_i + 1
        }

      end
    
    end
  end

  def tick
    roughly_now = Time.now.to_i
    @notifications.delete_if do |n|
      if roughly_now >= n[:next_check]
        meta = query_server n[:host], n[:port], "getinfo", 10, 3
        meta.shift
        processed = parseKeyValue meta
        puts processed
        puts "#{processed['clients']}, #{n[:at_least_x_players]}"
        if processed['clients'].to_i >= n[:at_least_x_players]
          ignore = send_request "BOT:PRIVMSG", "#{n[:notify]} (q3 notification) #{processed['sv_hostname']} has at least #{n[:at_least_x_players]}, join: unv://#{n[:host]}:#{n[:port]}"
          return true
        end
        puts "Updated notification for #{n[:host]}, checking again in 30s"
        n[:next_check] = roughly_now + 30
      end
      return false
    end
  end

end

q3 = Q3.new "unv", ARGV[0], ARGV[1]

q3.describe "Query Quake3-Compatible Servers"
q3.help_topic "unv info <server address> [port]", "Report the summary of a server (port defaults to 27960 if not specified)"
q3.help_topic "unv status <server address> [port]", "Get basic details of a server"
q3.help_topic "unv notify <nick or channel> <number of players> <server address> [port]", "Notify a user or channel if a certain number of players are on a q3 server"
q3.respond_to_help true

begin
  q3.subscribe_to "PRIVMSG"
  q3.subscribe_to "NOTICE"

  q3.run

rescue ZMQ::ContextError => e
  p e.inspect

rescue SystemExit, Interrupt
  # probably ctrl-c, this is okay :)

ensure
  q3.cleanup

end