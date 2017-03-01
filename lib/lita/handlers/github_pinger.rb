module Lita
  module Handlers
    class GithubPinger < Handler

      ####
      # ENGINEER NOTIFICATION PREFERENCES
      ####

      # example entry:
      # "Taylor Lapeyre" => {
      #   :usernames => {
      #     :slack         => "taylor",
      #     :github        => "taylorlapeyre"
      #   },
      #   :github_preferences =>  {
      #     :frequency     => "only_mentions",
      #     :ping_location => "dm"
      #   },
      #   :travis_preferences => {
      #     :frequency => "only_failures"
      #   }
      #}
      #
      # :github_preferences[:ping_location] can be...
      #  - "dm"
      #  - "eng-pr" (pings you in #eng-pr)
      #  default: "dm"
      #
      # :github_preferences[:frequency] can be
      #  - "all_discussion" (pings you about any comments on your PRs and @mentions)
      #  - "only_mentions" (will only ping you when you are explicitly @mentioned)
      #  - "off"
      #  default: "all_discussion"
      #
      # :travis_preferences[:frequency] can be
      #  - "only_passes"
      #  - "only_failures"
      #  - "everything"
      #  - "off"
      #  default: "all_discussion"
      config :engineers, type: Hash, required: true

      http.post("/ghping", :ghping)

      def ghping(request, response)
        body = MultiJson.load(request.body)
        puts "########## Event: #{body['action']} ##########"
        puts "keys: #{body.keys}"
        if body['pull_request']
          puts "pull_request.keys: #{body['pull_request'].keys}"
          puts "pull_request: #{body['pull_request']}"
        end
        username = body && body['user'] && body['user']['login']
        prid = body && body['number']

        if body['review']
          puts "found review: #{body['review']}, #{body['action']}, #{body['pull_request']}"
        end

        case body['action']
        when /review_requested/
          puts "review_requested: #{username}"
          act_on_review_requested(body, response)
        when /review_request_removed/
          puts "review_request_removed: #{username}"
          act_on_review_request_removed(body, response)
        when /submitted/
          puts "submitted: #{username}"
          act_on_submitted(body, response)
        when /unassigned/
          puts "#{username} unassigned from #{prid}"
          act_on_review_request_removed(body, response)
        when /opened/
          puts "#{username} opened from #{prid}"
        when /assigned/
          act_on_assign(body, response)
        else
          if body['comment']
            act_on_comment(body, response)

          elsif body["context"] == "continuous-integration/codeship"
            puts "codeship message"
          else
            puts "unknown event! #{body['action']}"
            puts "body: #{body}"
          end
        end
      end

      def act_on_review_requested(body, response)
        requested_reviewer_login = body["requested_reviewer"]["login"]
        requested_reviewer = find_engineer(github: requested_reviewer_login)
        url = body["pull_request"]["html_url"]
        title = body["pull_request"]["title"]
        message = "*Heads up!* Your review has been requested on #{url} '#{title}'"
        puts message
        send_dm(requested_reviewer[:usernames][:slack], message)
      end

      def act_on_review_request_removed(body, response)
        requested_reviewer_login = body["requested_reviewer"]["login"]
        requested_reviewer = find_engineer(github: requested_reviewer_login)
        url = body["pull_request"]["html_url"]
        title = body["pull_request"]["title"]
        message = "*Heads up!* You've been un-assigned from #{url} '#{title}'"
        puts message
        send_dm(requested_reviewer[:usernames][:slack], message)
      end

      def act_on_submitted(body, response)

        reviewer_login = body["review"]["user"]['login']
        review_body = body["review"]["body"]
        review_state = case body["review"]['state']
                        when "approved"
                          ":thumbsup: approved"
                        when "changes_requested"
                         ':rotating_light: requested changes'
                        when 'commented'
                          ':thought_balloon: commented'
                       end

        author_login = body["pull_request"]["user"]["login"]
        author = find_engineer(github: author_login)

        url = body["pull_request"]["html_url"]
        title = body["pull_request"]["title"]
        message = "#{reviewer_login} has #{review_state} #{url} '#{title}'\n>#{review_body}"
        puts message
        send_dm(author[:usernames][:slack], message)
      end

      def act_on_assign(body, response)
        type = detect_type(body)

        if type.nil?
          puts 'Neither pull request or issue detected, exiting...'
          return
        end

        puts "Detected that someone got assigned to a #{type.tr('_', ' ')}."

        assignee_login = body[type]['assignee']['login']
        assignee = find_engineer(github: assignee_login)

        puts "#{assignee} determined as the assignee."

        url = body[type]['html_url']

        message = "*Heads up!* You've been assigned to review a #{type.tr('_', ' ')}:\n#{url}"

        puts "Sending DM to #{assignee}..."
        send_dm(assignee[:usernames][:slack], message)

        response
      end

      def act_on_comment(body, response)
        puts "Detected a comment. Extracting data... "

        comment_url = body["comment"]["html_url"]
        comment     = body["comment"]["body"]
        context     = body["pull_request"] || body["issue"]

        commenter = find_engineer(github: body["comment"]["user"]["login"])
        pr_owner  = find_engineer(github: context["user"]["login"])
        lita_commenter = Lita::User.fuzzy_find(commenter[:usernames][:slack])

        puts "Reacting to PR comment #{comment_url}"
        puts "Found commenter #{commenter}"
        puts "Found lita_commenter #{lita_commenter}"
        puts "Found pr owner #{pr_owner}"

        # Sanity Checks - might be a new engineer around that hasn't set up
        # their config.

        engineers_to_ping = []
        # automatically include the creator of the PR, unless he's
        # commenting on his own PR

        if commenter != pr_owner && ["all_discussion", nil].include?(pr_owner[:github_preferences][:frequency])
          puts "PR owner was not the commenter, and has a :frequency of 'all_discussion' or nil"
          puts "Therefore, adding the PR owner to list of engineers to ping."
          engineers_to_ping << pr_owner
        end

        # Is anyone mentioned in this comment?
        if comment.include?("@")
          puts "Found @mentions in the body of the comment! Extracting usernames... "

          # get each @mentioned engineer in the comment
          mentions = comment
            .split('@')[1..-1] # "a @b @c d" => ["b ", "c d"]
            .map { |snip| snip.split(' ').first } # ["b ", "c d"] => ["b", "c"]
            .map { |name| name.gsub(/[^0-9a-z\-_]/i, '') }

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
          next if engineer[:github_preferences][:frequency] == "off"

          case engineer[:github_preferences][:ping_location]
          when "dm", nil
            puts "Preference was either 'dm' or nil, so sending DM."
            private_message  = "New PR comment from <@#{lita_commenter.id}|#{commenter[:usernames][:slack]}>:\n"
            private_message += "#{comment_url}\n#{comment}"
            send_dm(engineer[:usernames][:slack], private_message)
          when "eng-pr", "eng_pr"
            puts "Preference was either 'eng-pr' or 'eng_pr', so alerting #eng-pr."
            public_message  = "@#{engineer[:usernames][:slack]}, new PR mention: "
            public_message += "#{comment_url}\n#{comment}"
            alert_eng_pr(public_message)
          end
        end

        puts "GitHub Hook successfully processed."

        response
      end

      def alert_eng_pr(message)
        puts "Alerting #eng-pr about content #{message[0..5]}... "
        room = Lita::Room.fuzzy_find("testing")
        source = Lita::Source.new(room: room)
        robot.send_message(source, message)
        puts "Done."
      end

      def find_engineer(slack: nil, github: nil, name: nil)
        if name
          return config.engineers[name]
        end

        config.engineers.values.select do |eng|
          if slack
            eng[:usernames][:slack] == slack
          elsif github
            eng[:usernames][:github] == github
          end
        end.first
      end

      def send_dm(username, content)
        puts "Sending DM to #{username} with content:"
        puts "  #{content}"
        if user = find_user(username)
          puts "Found user: #{user.inspect}"
          source = Lita::Source.new(user: user)
          robot.send_message(source, content)
          puts "Done."
        else
          puts "Could not find user with name #{username}"
          alert_eng_pr("Could not find user with name #{username}")
        end
      end

      def find_user(username)
        Lita::User.fuzzy_find(username) || Lita::User.fuzzy_find(username.capitalize)
      end

      def detect_type(body)
        if body['pull_request']
          'pull_request'
        elsif body['issue']
          'issue'
        end
      end
    end

    Lita.register_handler(GithubPinger)
  end
end
