require "spec_helper"
require "json"

describe Lita::Handlers::GithubPinger, lita_handler: true do
  before do
    registry.config.handlers.github_pinger.engineers = {
      'Taylor' => {
        usernames: {
          slack: 'taylor',
          github: 'taylorlapeyre'
        }
      }
    }
  end

  it "will respond" do
    send_message("comments up @taylorlapeyre)")
    expect(replies.count).to eq 0
  end

  it 'will do the thing' do
    response = http.post("/ghping", '{"hello": "world", "events": ["pull_request_review_comment"]}')
    expect(response.body).to_not be_nil
  end
end
