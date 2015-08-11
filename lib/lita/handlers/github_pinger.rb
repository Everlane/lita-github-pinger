module Lita
  module Handlers
    class GithubPinger < Handler

      config :engineers, type: Array, required: true

      http.post("/ghping", :ghping)

      def ghping(request, response)
        body = MultiJson.load(request.body)

        if body["comment"]
          thing     = body["pull_request"] || body["issue"]
          pr_url    = thing["html_url"]
          comment   = body["comment"]["body"]
          commenter = github_to_slack_username(body["comment"]["user"]["login"])

          usernames_to_ping = []
          # automatically include the creator of the PR, unless he's
          # commenting on his own PR
          if body["comment"]["user"]["login"] != thing["user"]["login"]
            usernames_to_ping << [thing["user"]["login"]]
          end


          # Is anyone mentioned in this comment?
          if comment.include?("@")
            # get each @mentioned username in the comment
            mentions = comment.split("@")[1..-1].map { |snip| snip.split(" ").first }

            # add them to the list of usernames to ping
            usernames_to_ping = usernames_to_ping.concat(mentions).uniq
          end

          # slackify all of the users
          usernames_to_ping.map! { |user| github_to_slack_username(user) }

          puts "Got a comment on something, sending messages to #{usernames_to_ping}"
          usernames_to_ping.each do |user|

            pref = find_engineer(slack: user)[:preference]
            case pref
            when "off"
              # do nothing
            when "dm", nil
              private_message  = "New PR comment from @#{commenter}:\n"
              private_message += "#{pr_url}\n#{comment}"
              send_dm(user, private_message)
            when "eng-pr", "eng_pr"
              public_message  = "@#{user}, new PR mention: "
              public_message += "#{pr_url}\n#{comment}" if user == usernames_to_ping.last
              alert_eng_pr(public_message)
            end

          end
        end

        response
      end

      def alert_eng_pr(message)
        room = Lita::Room.fuzzy_find("eng-pr")
        source = Lita::Source.new(room: room)
        robot.send_message(source, message)
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

      def github_to_slack_username(github_username)
        find_engineer(github: github_username)[:slack]
      end

      def send_dm(username, content)
        if user = Lita::User.fuzzy_find(username)
          source = Lita::Source.new(user: user)
          robot.send_message(source, content)
        else
          alert_eng_pr("Could not find user with name #{username}, please configure everbot.")
        end
      end
    end

    Lita.register_handler(GithubPinger)
  end
end
