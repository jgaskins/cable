require "schedule"

module Cable
  class WebsocketPinger
    @@seconds : Int32 | Float64 = 3

    def self.run_every(value : Int32 | Float64, &block)
      @@seconds = value

      yield

      @@seconds = 3
    end

    def self.start(socket : HTTP::WebSocket)
      new(socket).start
    end

    def self.seconds
      @@seconds
    end

    def initialize(@socket : HTTP::WebSocket)
    end

    def start
      runner = Schedule::Runner.new
      runner.every(Cable::WebsocketPinger.seconds.seconds) do
        raise Schedule::StopException.new("Stoped") if @socket.closed?
        @socket.send({type: "ping", message: Time.utc.to_unix_f}.to_json)
      end
    end
  end
end
