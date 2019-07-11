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

  describe 'act on assign' do
    before do
      Lita::Room.create_or_update(1, name: 'eng-pr')
      Lita::User.create(1, name: 'taylorlapeyre')
    end

    context 'pull request' do
      it 'sends direct message' do
        fake_json_request = {
          action: 'assigned',
          pull_request: {
            assignee: {
              login: 'taylorlapeyre'
            }
          }
        }.to_json

        response = http.post('/ghping', fake_json_request)

        expect(replies.first).to match("You've been assigned to review a pull request")
        expect(response.status).to eq(200)
      end
    end

    context 'issue' do
      it 'sends direct message' do
        fake_json_request = {
          action: 'assigned',
          issue: {
            assignee: {
                login: 'taylorlapeyre'
            }
          }
        }.to_json

        response = http.post('/ghping', fake_json_request)

        expect(replies.first).to match("You've been assigned to review a issue")
        expect(response.status).to eq(200)
      end
    end
  end
end
