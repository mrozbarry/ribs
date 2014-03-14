# Gems
require 'rubygems'
require 'bundler/setup'
require 'ffi-rzmq'

class Context

  def initialize( )
    @context = ZMQ::Context.create 1
    @publish = @context.socket(ZMQ::PUB)
    @reply = @context.socket(ZMQ::REP)

    @poll = ZMQ::Poller.new
    @poll.register_readable @reply
    @poll.register_writable @publish
  end

  def publish_bind( protocol, host, port )
    connector = protocol.to_s + "://" + host.to_s + ":" + port.to_s
    puts "Publish Connector listening on " + connector
    @publish.bind( connector  )
  end

  def reply_bind( protocol, host, port )
    connector = protocol.to_s + "://" + host.to_s + ":" + port.to_s
    puts "Reply Connector listening on " + connector
    @reply.bind( connector )
  end

  def publish( type, message )
    msg = ZMQ::Message.new( type.to_s + " -> " + message.to_s )
    @publish.sendmsg msg
  end

  def reply( data )
    msg = ZMQ::Message.new data
    @reply.sendmsg msg
  end

  def process
    messages = []
    @poll.poll_nonblock

    @poll.readables.each do |sock|
      msg = ""
      sock.recv_string msg, ZMQ::DONTWAIT
      args = msg.split " -> ", 2
      messages << args
    end
    return messages
  end

end
