# Cable

It's like [ActionCable](https://guides.rubyonrails.org/action_cable_overview.html) (of course, not so powerful), but you know, for Crystal

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     cable:
       github: fernandes/cable
   ```

2. Run `shards install`

## Usage

```crystal
require "cable"
```

### With Lucky

On your `src/app_server.cr` add the `Cable::Handler` before `Lucky::RouteHandler`

```crystal
class AppServer < Lucky::BaseAppServer
  def middleware
    [
      WebsocketHandler.new,
      Lucky::RouteHandler.new,
    ]
   end
end
```

After that, you need to configure your `Cable`, using:

```crystal
Cable.configure do |settings|
  settings.route = "/cable"    # the URL your JS Client will connect
  settings.token = "token"     # The query string parameter used to get the token
end
```

Then you need to implement a few classes

The most important (and needs to be named `ApplicationCable::Connection`)

```crystal
module ApplicationCable
  class Connection < Cable::Connection
    def connect
      # Implement your Auth logic, something like
      JWT.decode(auth_token, Lucky::Server.settings.secret_key_base, JWT::Algorithm::HS256)
      self.identifier = payload["sub"].to_s
    end
  end
end
```

Then you need your base channel, just to make easy to aggregate your app's cables logic

```crystal
module ApplicationCable
  class Channel < Cable::Channel
  end
end
```

Then create your cables, as much as your want!! Let's setup a `ChatChannel` as example:

```crystal
class ChatChannel < ApplicationCable::Channel
  def subscribed
    # We don't support stream_for, needs to generate your own unique string
    stream_from "chat_#{params["room"]}"
  end

  def receive(data)
    broadcast_message = {} of String => String
    broadcast_message["message"] = data["message"].to_s
    broadcast_message["current_user_id"] = connection.identifier
    ChatChannel.broadcast_to("chat_#{params["room"]}", broadcast_message)
  end

  def perform(action, action_params)
    user = UserQuery.new.find(connection.identifier)
    user.away if action == "away"
    user.status(action_params["status"]) if action == "status"
    ChatChannel.broadcast_to("chat_#{params["room"]}", {
      "user"      => user.email,
      "performed" => action.to_s,
    })
  end

  def unsubscribed
    # You can do any action after client closes connection
    user = UserQuery.new.find(connection.identifier)
    user.logout
  end
end
```

Check below on the JavaScript section how to communicate with the Cable backend

## JavaScript

It works with [ActionCable](https://www.npmjs.com/package/actioncable) JS Client out-of-the-box!! Yeah, that's really cool no? If you need to adapt, make a hack, or something like that?! No, you don't need! Just read the few lines below and start playing with Cable in 5 minutes!

If you are using Rails, then you already has a `app/assets/javascripts/cable.js` file that requires `action_cable`, you just need to connect to the right URL (don't forgot the settings you used), to authenticate using JWT use something like:

```js
(function() {
  this.App || (this.App = {});

  App.cable = ActionCable.createConsumer(
    "ws://localhost:5000/cable?token=JWT_TOKEN" // if using the default options
  );
}.call(this));
```

then on your `app/assets/javascripts/channels/chat.js`

```js
App.channels || (App.channels = {});

App.channels["chat"] = App.cable.subscriptions.create({
  channel: "ChatChannel",
  params: {
    room: "1"
  }
}, {
  connected: function() {
    return console.log("ChatChannel connected");
  },
  disconnected: function() {
    return console.log("ChatChannel disconnected");
  },
  received: function(data) {
    return console.log("ChatChannel received", data);
  },
  rejected: function() {
    return console.log("ChatChannel rejected");
  },
  away: function() {
    return this.perform("away");
  },
  status: function(status) {
    return this.perform("status", {
      status: status
    });
  }
});
```

Then on your Browser console you can see the message:

> ChatChannel connected

After you load, then you can broadcast messages with:

```js
App.channels["chat"].send({message: "Hello World"})
```

And performs an action with:

```js
App.channels["chat"].perform("status", {status: "My New Status"});
```

## TODO

After reading the docs, I realized I'm using some weird naming for variables / methods, so

- [ ] Add an async/local adapter (make tests, development and small deploys simpler)
- [ ] Need to make connection use identifier
- [ ] Add `identified_by :current_user` to `Cable::Connection`
- [ ] Give better methods to reject a connection
- [ ] Refactor, Connection class is soooo bloated

## First Class Citizen

- [ ] Better integrate with Lucky, maybe with generators, or something else?
- [ ] Add support for Kemal
- [ ] Add support for Amber

Idea is create different modules, `Cable::Lucky`, `Cable::Kemal`, `Cable::Amber`, and make it easy to use with any crystal web framework

## Contributing

You know, fork-branch-push-pr 😉 don't be shy, participate as you want!

## Contributors

- [Celso Fernandes](https://github.com/fernandes)
