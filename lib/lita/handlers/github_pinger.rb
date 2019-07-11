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
      end

      def act_on_deployment_status(body, response)
        repo_name     = body['repository']['name']
        deploy_ref    = body['deployment']['ref']
        deploy_env    = body['deployment']['environment']
        deploy_sha    = body['deployment']['sha']
        deploy_status = body['deployment_status']['state']

        deploy_name = "#{repo_name} / #{deploy_ref} / #{deploy_env}"

        puts "Deployment status update for #{deploy_name}: #{deploy_status}"

        # We sometimes see a combination of ref and env that works out to [sha, branch]
        # Let’s only worry about *real* [ref, env] pairs
        if deploy_sha.start_with? deploy_ref
          puts "Duplicate status update (#{deploy_name})"
          return
        end

        deploy_owner = find_engineer github: body['deployment']['creator']['login']

        if !deploy_owner
          puts "Couldn’t find owner of deploy (#{deploy_name})"
          return
        end

        owner_username = deploy_owner[:usernames][:slack]

        if deploy_status == 'success'
          send_dm owner_username, "Your deployment of #{deploy_ref} to #{deploy_env} is complete!"
        elsif ['failure', 'error'].include? deploy_status
          send_dm owner_username, "Your deployment of #{deploy_ref} to #{deploy_env} failed."
        end
      end

      def get_next_round_robin_reviewer
        engineers_with_rr_enabled = config.engineers.values.select { |eng| eng[:enable_round_robin] }
        next_reviewer = redis.get(RR_REDIS_KEY)

        if next_reviewer.nil?
          next_reviewer = engineers_with_rr_enabled[0][:usernames][:slack]
        end

        next_reviewer
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
