require "mutex"
require "set"

module Cable
  alias Channels = Set(Cable::Channel)

  def self.server
    @@server ||= Server.new
  end

  def self.restart
    if current_server = @@server
      current_server.shutdown
    end
    @@server = Server.new
  end

  class Server
    getter connections = {} of String => Connection
    getter redis_subscribe = Redis::Connection.new(URI.parse(Cable.settings.url))
    getter redis_publish = Redis::Client.new(URI.parse(Cable.settings.url))
    getter fiber_channel = ::Channel({String, String}).new

    @channels = {} of String => Channels
    @channel_mutex = Mutex.new

    def initialize
      subscribe
      process_subscribed_messages
    end

    def add_connection(connection)
      connections[connection.connection_identifier] = connection
    end

    def remove_connection(connection_id)
      connections.delete(connection_id).try(&.close)
    end

    def subscribe_channel(channel : Channel, identifier : String)
      @channel_mutex.synchronize do
        if !@channels.has_key?(identifier)
          @channels[identifier] = Channels.new
        end

        @channels[identifier] << channel
      end

      redis_subscribe.encode({"subscribe", identifier})
      redis_subscribe.flush
    end

    def unsubscribe_channel(channel : Channel, identifier : String)
      @channel_mutex.synchronize do
        if @channels.has_key?(identifier)
          @channels[identifier].delete(channel)

          if @channels[identifier].size == 0
            redis_subscribe.unsubscribe identifier

            @channels.delete(identifier)
          end

        else
          redis_subscribe.unsubscribe identifier
        end
      end
    end

    def publish(channel : String, message)
      redis_publish.publish(channel, message)
    end

    def send_to_channels(channel, message)
      @channels[channel].each do |channel|
        Cable::Logger.debug { "#{channel.class} transmitting #{message} (via streamed from #{channel.stream_identifier})" }
        channel.connection.socket.send({
          identifier: channel.identifier,
          message:    message,
        }.to_json)
      rescue IO::Error
      end
    end

    def debug
      Cable::Logger.debug { "-" * 80 }
      Cable::Logger.debug { "Some Good Information" }
      Cable::Logger.debug { "Connections" }
      @connections.each do |k, v|
        Cable::Logger.debug { "Connection Key: #{k}" }
      end
      Cable::Logger.debug { "Channels" }
      @channels.each do |k, v|
        Cable::Logger.debug { "Channel Key: #{k}" }
        Cable::Logger.debug { "Channels" }
        v.each do |channel|
          Cable::Logger.debug { "From Channel: #{channel.connection.connection_identifier}" }
          Cable::Logger.debug { "Params: #{channel.params}" }
          Cable::Logger.debug { "ID: #{channel.identifier}" }
          Cable::Logger.debug { "Stream ID:: #{channel.stream_identifier}" }
        end
      end
      Cable::Logger.debug { "-" * 80 }
    end

    def shutdown
      redis_subscribe.run({"unsubscribe"})
      redis_subscribe.close
      redis_publish.close
      connections.each do |k, v|
        v.close
      end
    end

    private def process_subscribed_messages
      server = self
      spawn do
        while received = fiber_channel.receive
          channel, message = received
          server.send_to_channels(channel, message)
        end
      end
    end

    private def subscribe
      spawn do
        redis_subscribe.subscribe("_internal") do |subscription|
          subscription.on_message do |channel, message|
            if channel == "_internal" && message == "debug"
              puts self.debug
            else
              fiber_channel.send({channel, message})
            end
          end
        end
      end
    end
  end
end
