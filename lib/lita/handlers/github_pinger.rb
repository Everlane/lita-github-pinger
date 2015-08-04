module Lita
  module Handlers
    class GithubPinger < Handler
      route(/assigned to (.*)\)/, :detect_comment, command: false)

      def detect_comment(message)
        log(message.user.metadata["name"] + " was detected as a github bot")
        return unless message.user.metadata["name"] == "github"
        pr_owner = message.matches[0][0]

        # side effects intentional
        found = config.engineers.any? do |eng|
          message.reply("@" + eng[:slack]) if eng[:github] == pr_owner
        end

        unless found
          message.reply("Could not find a slack username for #{pr_owner}. Please configure everbot to include this username.")
        end
      end
    end

    Lita.register_handler(GithubPinger)
  end
end
