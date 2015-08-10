module Lita
  module Handlers
    class GithubPinger < Handler

      config :engineers, type: Array, required: true

      route(/@(\w*)/, :detect_comment, command: false)

      http.post "/ghping", :ghping

      def ghping(request, response)
        body = MultiJson.load(request.body)
        pp body
        send_dm("taylor", "```#{body}```")
        response
      end

      def alert_eng_pr(message)
        room = Lita::Room.fuzzy_find("eng")
        source = Lita::Source.new(room: room)
        robot.send_message(source, message)
      end

      def send_dm(username, content)
        if user = Lita::User.fuzzy_find(username)
          source = Lita::Source.new(user: user)
          robot.send_message(source, content)
        else
          puts "Could not find user with name #{username}"
        end
      end

      def detect_comment(message)
        return unless message.user.metadata["name"] == "" # Integrations don't have names
        mentioned_username = message.matches[0][0]

        config.engineers.each do |eng|
          if eng[:github] == mentioned_username

            case eng[:preference]
            when "dm"
              send_dm(eng[:slack], message.message.body)
            when "eng_pr", "eng-pr"
              message.reply(eng[:slack] + ": " + message.message.body)
            when "off"
              return
            else
              send_dm(eng[:slack], message.message.body)
            end

            return
          end
        end

        message.reply("Could not find a slack username for #{mentioned_username}. Please configure everbot to include this username.")
      end
    end

    Lita.register_handler(GithubPinger)
  end
end
