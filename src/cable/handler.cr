require "http/server"

module Cable
  class Handler(T)
    include HTTP::Handler

    def on_error(&@on_error : Exception ->) : self
      self
    end

    def call(context)
      return call_next(context) unless ws_route_found?(context) && websocket_upgrade_request?(context)

      remote_address = context.request.remote_address
      path = context.request.path
      Cable::Logger.debug { "Started GET \"#{path}\" [WebSocket] for #{remote_address} at #{Time.utc.to_s}" }

      context.response.headers["Sec-WebSocket-Protocol"] = "actioncable-v1-json"

      ws = HTTP::WebSocketHandler.new do |socket, context|
        connection = T.new(context.request, socket)
        connection_id = connection.connection_identifier
        Cable.server.add_connection(connection)

        # Send welcome message to the client
        socket.send({type: "welcome"}.to_json)

        Cable::WebsocketPinger.start socket

        # Handle incoming message and echo back to the client
        socket.on_message do |message|
          begin
            connection.receive(message)
          rescue e : Exception
            Cable::Logger.error { "Exception: #{e.message}" }
          end
        end

        socket.on_close do
          Cable.server.remove_connection(connection_id)
          Cable::Logger.debug { "Finished \"#{path}\" [WebSocket] for #{remote_address} at #{Time.utc.to_s}" }
        end
      end

      Cable::Logger.debug { "Successfully upgraded to WebSocket (REQUEST_METHOD: GET, HTTP_CONNECTION: Upgrade, HTTP_UPGRADE: websocket)" }
      ws.call(context)
    end

    private def websocket_upgrade_request?(context)
      return unless upgrade = context.request.headers["Upgrade"]?
      return unless upgrade.compare("websocket", case_insensitive: true) == 0

      context.request.headers.includes_word?("Connection", "Upgrade")
    end

    private def ws_route_found?(context)
      return true if context.request.path === Cable.settings.route
      false
    end
  end
end
