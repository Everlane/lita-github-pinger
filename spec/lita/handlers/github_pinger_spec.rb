require "spec_helper"

describe Lita::Handlers::GithubPinger, lita_handler: true do
  it "will respond" do
    send_message("assigned to taylorlapeyre)")
    expect(replies.count).to eq 0
  end
end
