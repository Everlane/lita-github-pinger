module Lita
  module Handlers
    class GithubPinger < Handler

      config :engineers, type: Array, required: true

      http.post("/ghping", :ghping)

      def ghping(request, response)

        puts "########## New GH PR Event! ##########"
        body = MultiJson.load(request.body)

        if body["comment"]
          puts "Detected a comment. Extracting data... "

          thing     = body["pull_request"] || body["issue"]
          pr_url    = thing["html_url"]
          comment   = body["comment"]["body"]
          commenter = body["comment"]["user"]["login"]
          pr_owner  = thing["user"]["login"]

          puts "Found PR #{pr_url}"
          puts "Found commenter #{commenter}"
          puts "Found pr owner #{pr_owner}"

          usernames_to_ping = []
          # automatically include the creator of the PR, unless he's
          # commenting on his own PR
          if commenter != pr_owner
            puts "Commenter is not the pr owner. Adding to list of usernames to ping."
            usernames_to_ping << pr_owner
          end

          puts "So far, github usernames to ping: #{usernames_to_ping}"

          # Is anyone mentioned in this comment?
          if comment.include?("@")
            puts "Found @mentions in the body of the comment! Extracting usernames... "

            # get each @mentioned username in the comment
            mentions = comment.split("@")[1..-1].map { |snip| snip.split(" ").first }
            puts "Done. (Got #{mentions})"

            # add them to the list of usernames to ping
            usernames_to_ping = usernames_to_ping.concat(mentions).uniq
          end

          puts "New list of github usernames to ping: #{usernames_to_ping}."
          puts "Converting github usernames to slack usernames... "

          # slackify all of the users
          usernames_to_ping.map! { |user| github_to_slack_username(user) }

          puts "Done. (Got #{usernames_to_ping})"

          puts "Starting pinging process for each engineer..."
          usernames_to_ping.compact.each do |user|

            pref = find_engineer(slack: user)[:preference]

            puts "Found preference #{pref.inspect} for user #{user}"

            case pref
            when "off"
              puts "Preference was 'off', so doing nothing."
            when "dm", nil
              puts "Preference was either 'dm' or nil, so sending DM."
              private_message  = "New PR comment from @#{commenter}:\n"
              private_message += "#{pr_url}\n#{comment}"
              send_dm(user, private_message)
            when "eng-pr", "eng_pr"
              puts "Preference was either 'eng-pr' or 'eng_pr', so alerting #eng-pr."
              public_message  = "@#{user}, new PR mention: "
              public_message += "#{pr_url}\n#{comment}" if user == usernames_to_ping.last
              alert_eng_pr(public_message)
            end

          end

          puts "GitHub Hook successfully processed."
        end

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

      def github_to_slack_username(github_username)
        engineer = find_engineer(github: github_username)
        engineer[:slack] if engineer
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
