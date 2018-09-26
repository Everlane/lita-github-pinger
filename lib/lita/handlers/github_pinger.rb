require 'json'

module Lita
  module Handlers
    RR_REDIS_KEY = 'lita-github-pinger:roundrobin'.freeze
    REVIEW_REDIS_KEY = 'lita-github-pinger:reviewrequests'.freeze

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
      #     :ping_location => "dm",
      #     :notify_about_review_requests: true,
      #     :notify_about_assignment: true,
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
      # :status_preferences[:frequency] can be
      #  - "only_passes"
      #  - "only_failures"
      #  - "everything"
      #  - "off"
      #  default: "everything"
      config :engineers, type: Hash, required: true
      config :enable_round_robin, types: [TrueClass, FalseClass]

      http.post("/ghping", :ghping)

      def ghping(request, response)
        puts "########## New GitHub Event! ##########"
        body = MultiJson.load(request.body)

        puts body["action"]
        puts body["state"]

        if body['deployment_status']
          act_on_deployment_status(body, response)
        end

        if body["comment"] && body["action"] == "created"
          act_on_comment(body, response)
        end

        if body["action"] && body["action"] == "assigned"
          act_on_assign(body, response)
        end

        if body["action"] && body["action"] == "review_requested"
          act_on_review_requested(body, response)
        end

        if body["action"] && body["action"] == "labeled"
          act_on_pr_labeled(body, response)
        end

        if body["state"] && body["state"] == "success"
          act_on_build_success(body, response)
        end

        if body["state"] && body["state"] == "failure"
          act_on_build_failure(body, response)
        end
      end

      def act_on_build_failure(body, response)
        commit_url = body["commit"]["html_url"]
        committer = find_engineer(github: body["commit"]["committer"]["login"])

        puts "Detected a status failure for commit #{body["sha"]}"
        message = ":x: Your commit failed CI."
        message += "\n#{commit_url}"

        if committer
          frequency = if committer[:travis_preferences]
            committer[:travis_preferences][:frequency]
          else
            committer[:status_preferences][:frequency]
          end

          return if ["off", "only_passes"].include?(frequency)

          send_dm(committer[:usernames][:slack], message)
        else
          puts "Could not find configuration for GitHub username " + body["commit"]["committer"]["login"]
        end

        response
      end

      def act_on_build_success(body, response)
        commit_url = body["commit"]["html_url"]
        committer = find_engineer(github: body["commit"]["committer"]["login"])

        puts "Detected a status success for commit #{body["sha"]}"
        message = ":white_check_mark: Your commit has passed CI."
        message += "\n#{commit_url}"

        if committer
          frequency = if committer[:travis_preferences]
            committer[:travis_preferences][:frequency]
          else
            committer[:status_preferences][:frequency]
          end

          return if ["off", "only_failures"].include?(frequency)

          send_dm(committer[:usernames][:slack], message)
        else
          puts "Could not find configuration for GitHub username " + body["commit"]["committer"]["login"]
        end

        response
      end

      def act_on_assign(body, response)
        type = detect_type(body)

        if type.nil?
          puts "Neither pull request or issue detected, exiting..."
          return
        end

        puts "Detected that someone got assigned to a #{type.tr('_', ' ')}."

        assignee_login = body[type]["assignee"]["login"]
        assignee = find_engineer(github: assignee_login)

        puts "Looking up preferences..."
        should_notify = assignee[:github_preferences][:notify_about_assignment]

        if !should_notify
          puts "will not notify, preference for :github_preferences[:notify_about_assignment] is not true"
          return response
        end

        puts "#{assignee} determined as the assignee."

        url = body[type]["html_url"]

        message = "*Heads up!* You've been assigned to a #{type.tr('_', ' ')}:\n#{url}"

        puts "Sending DM to #{assignee}..."
        send_dm(assignee[:usernames][:slack], message)

        response
      end

      def act_on_review_requested(body, response)
        puts "Detected a review request."

        puts "looking at previously notified reviewers for this PR"

        pr = body["pull_request"]

        url = pr["html_url"]

        notified_engineers = redis.get(REVIEW_REDIS_KEY + ":" + url)

        notified_engineers = if notified_engineers
          JSON.parse(notified_engineers)
        else
          []
        end

        pr["requested_reviewers"].each do |reviewer|
          engineer = find_engineer(github: reviewer["login"])

          if !engineer
            puts "Could not find engineer #{reviewer["login"]}"
            next
          end

          if notified_engineers.include?(reviewer["login"])
            puts "#{reviewer["login"]} has already been notified to review PR, skipping..."
            next
          end

          puts "#{engineer} determined as a reviewer."

          puts "Looking up preferences..."
          should_notify = engineer[:github_preferences][:notify_about_review_requests]

          if !should_notify
            puts "will not notify, preference for :github_preferences[:notify_about_review_requests] is not true"
          else
            message = "You've been asked to review a pull request:\n#{url}"
            send_dm(engineer[:usernames][:slack], message)
            notified_engineers.push(reviewer["login"])
          end
        end

        redis.set(REVIEW_REDIS_KEY + ":" + url, notified_engineers.to_json)

        response
      end

      def act_on_pr_labeled(body, response)
        type = detect_type(body)
        puts "Detected that someone labeled a #{type.tr('_', ' ')}."

        if type.nil?
          puts "Neither pull request or issue detected, exiting..."
          return
        end

        if body["pull_request"]["labels"].none? { |label| label["name"].downcase.include?('review') }
          puts "Labels do not include a review label, exiting..."
          return
        end

        if config.enable_round_robin
          puts "round robin is enabled, selecting the next engineer.."

          chosen_reviewer = get_next_round_robin_reviewer

          pr_owner = find_engineer(github: body["pull_request"]["user"]["login"])
          pr_owner = pr_owner[:usernames][:slack] unless pr_owner.nil?

          if chosen_reviewer === pr_owner
            update_next_round_robin_reviewer
            chosen_reviewer = get_next_round_robin_reviewer
          end

          puts "#{chosen_reviewer} determined as the reviewer."

          url = body[type]["html_url"]

          message_for_reviewer = <<-eos
            You’re next in line to look at a PR! There’s no obligation to submit a review, but take a look and familiarize yourself with the code as time allows.
            If the PR looks particularly interesting or well-authored, nominate it as a PR of the Week.
          eos
          message_for_owner = <<-eos
            #{chosen_reviewer} has been selected via round-robin to examine #{body["pull_request"]["html_url"]}.
            Round-robin assignment is not an obligation to submit a review. Seek reviewers as appropriate.
          eos

          puts "Sending DM to #{chosen_reviewer}..."
          send_dm(chosen_reviewer, message_for_reviewer)

          if pr_owner
            puts "Notifying #{pr_owner} of assignment."
            send_dm(pr_owner, message_for_owner)
          else
            puts "Couldn't find a config for pr owner #{body["pull_request"]["user"]["login"]}. Make sure they are in the lita config!"
            puts "Skipping notifying PR owner of RR assignment."
          end

          update_next_round_robin_reviewer
          
          response
        end
      end

      def act_on_deployment_status(body, response)
        deploy_ref    = body['deployment']['ref']
        deploy_env    = body['deployment']['environment']
        deploy_status = body['deployment_status']['state']

        puts "Deployment status update for #{deploy_ref} to #{deploy_env}: #{deploy_status}"

        deploy_owner = find_engineer github: body['deployment']['creator']['login']

        if !deploy_owner
          puts 'Couldn’t find owner of deploy'
          return
        end

        owner_username = deploy_owner[:usernames][:slack]

        if deploy_status == 'success'
          send_dm owner_username, "Your deployment of #{deploy_ref} to #{deploy_env} is complete!"
        elsif ['failure', 'error'].include? deploy_status
          send_dm owner_username, "Your deployment of #{deploy_ref} to #{deploy_env} failed."
        end
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
            .split("@")[1..-1] # "a @b @c d" => ["b ", "c d"]
            .map { |snip| snip.split(" ").first } # ["b ", "c d"] => ["b", "c"]
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

      def get_next_round_robin_reviewer
        engineers_with_rr_enabled = config.engineers.values.select { |eng| eng[:enable_round_robin] }
        next_reviewer = redis.get(RR_REDIS_KEY)

        if next_reviewer.nil?
          next_reviewer = engineers_with_rr_enabled[0][:usernames][:slack]
        end

        next_reviewer
      end

      def update_next_round_robin_reviewer
        engineers_with_rr_enabled = config.engineers.values.select { |eng| eng[:enable_round_robin] }
        current_reviewer = get_next_round_robin_reviewer

        current_reviewer_index = engineers_with_rr_enabled.find_index do |eng|
          eng[:usernames][:slack] == current_reviewer
        end

        next_reviewer_index = (current_reviewer_index + 1) % engineers_with_rr_enabled.length
        next_reviewer = engineers_with_rr_enabled[next_reviewer_index][:usernames][:slack]

        redis.set(RR_REDIS_KEY, next_reviewer)
      end

      def alert_eng_pr(message)
        puts "Alerting #eng-pr about content #{message[0..5]}... "
        room = Lita::Room.fuzzy_find("eng-pr")
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
        puts "Sending DM to #{username} with content #{content[0..5]}... "
        if user = Lita::User.fuzzy_find(username)
          source = Lita::Source.new(user: user)
          robot.send_message(source, content)
          puts "Done."
        else
          alert_eng_pr("Could not find user with name #{username}, please configure everbot.")
        end
      end

      def detect_type(body)
        if body["pull_request"]
          "pull_request"
        elsif body["issue"]
          "issue"
        end
      end
    end

    Lita.register_handler(GithubPinger)
  end
end
