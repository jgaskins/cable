module Cable
  class Channel
    class CloseRedisFiber < Exception; end

    CHANNELS = {} of String => Cable::Channel.class

    macro inherited
      Cable::Channel::CHANNELS[self.name] = self
    end

    getter params
    getter identifier
    getter connection
    getter stream_identifier : String?

    def initialize(@connection : Cable::Connection, @identifier : String, @params : Hash(String, Cable::Payload::RESULT))
    end

    def subscribed
    end

    def close
      if stream_identifier = @stream_identifier
        Cable.server.unsubscribe_channel(channel: self, identifier: stream_identifier)
      end
      Cable::Logger.debug { "#{self.class.name} stopped streaming from #{identifier}" }
      unsubscribed
    end

    def unsubscribed
    end

    def receive(message)
    end

    def perform(action, message)
    end

    def stream_from(stream_identifier)
      @stream_identifier = stream_identifier
      Cable.server.subscribe_channel(channel: self, identifier: stream_identifier)
      Cable::Logger.debug { "#{self.class} is streaming from #{stream_identifier}" }
    end

    def self.broadcast_to(channel : String, message : String)
      Cable::Logger.debug { "[ActionCable] Broadcasting to #{channel}: #{message}" }
      Cable.server.publish(channel, message)
    end

    def self.broadcast_to(channel : String, message : JSON::Any)
      Cable::Logger.debug { "[ActionCable] Broadcasting to #{channel}: #{message}" }
      Cable.server.publish(channel, message.to_json)
    end

    def self.broadcast_to(channel : String, message : Hash(String, String))
      Cable::Logger.debug { "[ActionCable] Broadcasting to #{channel}: #{message}" }
      Cable.server.publish(channel, message.to_json)
    end
  end
end
