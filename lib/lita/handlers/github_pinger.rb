module Lita
  module Handlers
    class GithubPinger < Handler

      GITHUB_PR_COMMENT_REGEX = /\[Everlane\/.*\] New comment on pull request #(\d+): (.+) \(assigned to (\w+)\)\nComment by (\w+)\n(.*)/

      config :engineers, type: Array, required: true

      route(GITHUB_PR_COMMENT_REGEX, :detect_comment, command: false)
      route(/testing/, :see_what_happens, command: false)

      def see_what_happens(message)
        message.reply message.message.body
      end

      def detect_comment(message)
        pr_id,
        pr_title,
        assigned_person,
        comment_author,
        comment_text = message.matches[0]

        # return unless message.user.metadata["name"] == "" # Integrations don't have names
        return unless comment_text.include?("@")

        mentioned_username = comment_text.split("@")[1].split(" ").first

        config.engineers.each do |engineer|
          if engineer[:github] == mentioned_username
            content = %Q{#{engineer[:slack]}, you were mentioned by #{comment_author}:
  http://github.com/everlane/everlane.com/pull/#{pr_id}
  > #{comment_text}
}
            message.reply(content)
            user = Lita::User.find_by_name(engineer[:slack])
            robot.send_message(user, content)
          end
        end
      end
    end

    Lita.register_handler(GithubPinger)
  end
end
