module Lita
  module Handlers
    class GithubPinger < Handler

      ####
      # ENGINEER NOTIFICATION PREFERENCES
      ####

      # example entry: {
      #   :slack         => "taylor"
      #   :github        => "taylorlapeyre"
      #   :frequency     => "only_mentions"
      #   :ping_location => "dm"
      #}
      #
      # :ping_location can be...
      #  - "dm"
      #  - "eng-pr" (pings you in #eng-pr)
      #  default: "dm"
      #
      # :frequency can be
      #  - "all_discussion" (pings you about any comments on your PRs and @mentions)
      #  - "only_mentions" (will only ping you when you are explicitly @mentioned)
      #  - "off"
      #  default: "all_discussion"
      config :engineers, type: Array, required: true

      http.post("/ghping", :ghping)

      def ghping(request, response)
        puts "########## New GH PR Event! ##########"
        body = MultiJson.load(request.body)

        if body["comment"]
          act_on_comment(body, response)
        end

        if body["action"] && body["action"] == "assigned"
          act_on_assign(body, response)
        end
      end

      def act_on_assign(body, response)
        puts "Detected that someone got assigned to a pull request."
        assignee = find_engineer(github: body["pull_request"]["assignee"]["login"])

        puts "#{assignee} determined as the assignee."

        pr_url   = body["pull_request"]["html_url"]
        message = "*Heads up!* You've been assigned to review a pull request:\n#{pr_url}"

        puts "Sending DM to #{assignee}..."
        send_dm(assignee[:slack], message)

        response
      end

      def act_on_comment(body, response)
        puts "Detected a comment. Extracting data... "

        comment_url = body["comment"]["html_url"]
        comment     = body["comment"]["body"]
        context     = body["pull_request"] || body["issue"]

        commenter = find_engineer(github: body["comment"]["user"]["login"])
        pr_owner  = find_engineer(github: context["user"]["login"])

        puts "Reacting to PR comment #{comment_url}"
        puts "Found commenter #{commenter}"
        puts "Found pr owner #{pr_owner}"

        # Sanity Checks - might be a new engineer around that hasn't set up
        # their config.

        engineers_to_ping = []
        # automatically include the creator of the PR, unless he's
        # commenting on his own PR

        if commenter != pr_owner && ["all_discussion", nil].include?(pr_owner[:frequency])
          puts "PR owner was not the commenter, and has a :frequency of 'all_discussion' or nil"
          puts "Therefore, adding the PR owner to list of engineers to ping."
          engineers_to_ping << pr_owner
        end

        # Is anyone mentioned in this comment?
        if comment.include?("@")
          puts "Found @mentions in the body of the comment! Extracting usernames... "

          # get each @mentioned engineer in the comment
          mentions = comment.split("@")[1..-1].map { |snip| snip.split(" ").first }

          puts "Done. Got #{mentions}"
          puts "Converting usernames to engineers..."

          mentioned_engineers = mentions.map { |username| find_engineer(github: username) }

          puts "Done. Got #{mentioned_engineers}"

          # add them to the list of usernames to ping
          engineers_to_ping = engineers_to_ping.concat(mentioned_engineers).uniq.compact
        end

        puts "New list of engineers to ping: #{engineers_to_ping}."
        puts "Starting pinging process for each engineer..."
        engineers_to_ping.each do |engineer|
          puts "looking at #{engineer}'s preferences..'"
          next if engineer[:frequency] == "off"

          case engineer[:ping_location]
          when "dm", nil
            puts "Preference was either 'dm' or nil, so sending DM."
            private_message  = "New PR comment from @#{commenter[:slack]}:\n"
            private_message += "#{comment_url}\n#{comment}"
            send_dm(engineer[:slack], private_message)
          when "eng-pr", "eng_pr"
            puts "Preference was either 'eng-pr' or 'eng_pr', so alerting #eng-pr."
            public_message  = "@#{engineer[:slack]}, new PR mention: "
            public_message += "#{comment_url}\n#{comment}"
            alert_eng_pr(public_message)
          end
        end

        puts "GitHub Hook successfully processed."

        response
      end

      def alert_eng_pr(message)
        puts "Alerting #eng-pr about content #{message[0..5]}... "
        room = Lita::Room.fuzzy_find("eng-pr")
        source = Lita::Source.new(room: room)
        robot.send_message(source, message)
        puts "Done."
      end

      def find_engineer(slack: nil, github: nil)
        config.engineers.select do |eng|
          if slack
            eng[:slack] == slack
          elsif github
            eng[:github] == github
          end
        end.first
      end

      def send_dm(username, content)
        puts "Sending DM to #{username} with content #{content[0..5]}... "
        if user = Lita::User.fuzzy_find(username)
          source = Lita::Source.new(user: user)
          robot.send_message(source, content)
          puts "Done."
        else
          alert_eng_pr("Could not find user with name #{username}, please configure everbot.")
        end
      end
    end

    Lita.register_handler(GithubPinger)
  end
end
