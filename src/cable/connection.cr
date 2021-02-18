require "uuid"

module Cable
  class Connection
    class UnathorizedConnectionException < Exception; end

    property internal_identifier : String = "0"
    getter connection_identifier : String

    # {
    #   "Turbo::StreamsChannel" => {
    #     "signed-stream-name" => my_channel,
    #   },
    # }
    CHANNELS = {} of String => Hash(String, Cable::Channel)

    getter socket
    getter id : UUID

    macro identified_by(name)
      property {{name.id}} = ""

      private def internal_identifier
        @{{name.id}}
      end
    end

    macro owned_by(type_definition)
      property {{type_definition.var}} : {{type_definition.type}}?
    end

    def initialize(@request : HTTP::Request, @socket : HTTP::WebSocket)
      @id = UUID.random
      @connection_identifier = "#{internal_identifier}-#{@id}"

      begin
        connect
      rescue e : UnathorizedConnectionException
        socket.close :normal_closure, "Farewell"
        Cable::Logger.debug { "An unauthorized connection attempt was rejected" }
      end
    end

    def connect
      raise Exception.new("Implement the `connect` method")
    end

    def close
      return true unless Connection::CHANNELS.has_key?(connection_identifier)
      Connection::CHANNELS[connection_identifier].each do |identifier, channel|
        channel.close
        Connection::CHANNELS[connection_identifier].delete(identifier)
      rescue e : IO::Error
      end
      socket.close
    end

    def reject_unauthorized_connection
      raise UnathorizedConnectionException.new
    end

    def receive(message)
      payload = Cable::Payload.new(message)

      return subscribe(payload) if payload.command == "subscribe"
      return message(payload) if payload.command == "message"
    end

    def subscribe(payload)
      channel = Cable::Channel::CHANNELS[payload.channel].new(
        connection: self, 
        identifier: payload.identifier,
        params: payload.channel_params
      )
      Connection::CHANNELS[connection_identifier] ||= {} of String => Cable::Channel
      Connection::CHANNELS[connection_identifier][payload.identifier] = channel
      channel.subscribed
      Cable::Logger.debug { "#{payload.channel} is transmitting the subscription confirmation" }
      socket.send({type: "confirm_subscription", identifier: payload.identifier}.to_json)
    end

    def message(payload)
      if channel = Connection::CHANNELS[connection_identifier][payload.identifier]?
        if payload.action?
          Cable::Logger.debug { "#{channel.class}#perform(\"#{payload.action}\", #{payload.data})" }
          channel.perform(payload.action, payload.data)
        else
          begin
            Cable::Logger.debug { "#{channel.class}#receive(#{payload.data})" }
            channel.receive(payload.data)
          rescue e : TypeCastError
          end
        end
      end
    end

    def self.broadcast_to(channel : String, message : String)
      Cable.server.publish(channel, message)
    end
  end
end
