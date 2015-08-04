require "spec_helper"

describe Lita::Handlers::GithubPinger, lita_handler: true do
  before do
    registry.config.handlers.github_pinger.engineers = [
      {
        slack: "taylor",
        github: "taylorlapeyre"
      },
      {
        slack: "petergao",
        github: "peteygao"
      },
      {
        slack: "matt",
        github: "mtthgn"
      },
      {
        slack: "bigsean",
        github: "telaviv"
      },
      {
        slack: "urich",
        github: "maalur"
      },
      {
        slack: "evan",
        github: "evantarrh"
      },
      {
        slack: "bsturd",
        github: "bsturdivan"
      },
      {
        slack: "jeff",
        github: "jeffmicklos"
      },
      {
        slack: "nan",
        github: "thenanyu"
      }
    ]
  end

  it "will respond" do
    send_message("comments up @taylorlapeyre)")
    expect(replies.count).to eq 0
  end
end
