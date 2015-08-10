module Lita
  module Handlers
    class GithubPinger < Handler

      config :engineers, type: Array, required: true

      route(/@(\w*)/, :detect_comment, command: false)

      def detect_comment(message)
        return unless message.user.metadata["name"] == "" # Integrations don't have names
        mentioned_username = message.matches[0][0]

        # side effects intentional
        found = config.engineers.any? do |eng|
          if eng[:github] == mentioned_username
            user = Lita::User.fuzzy_find(engineer[:slack])
            if user
              robot.send_message(user, "New PR comment! #{message.message.body}")
            else
              message.reply(eng[:slack] + ": " + message.message.body)
            end
          end
        end

        unless found
          message.reply("Could not find a slack username for #{pr_owner}. Please configure everbot to include this username.")
        end
      end
    end

    Lita.register_handler(GithubPinger)
  end
end
