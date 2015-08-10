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
    send_message(%q{
[Everlane/everlane.com] New comment on pull request #1137: More accurate location data and (by extension) working weather for factories (assigned to taylorlapeyre)
Comment by thenanyu
@taylorlapeyre hai
})
    expect(replies.last).to eq %q{taylor, you were mentioned by thenanyu:
  http://github.com/everlane/everlane.com/pulls/1137
  > @taylorlapeyre hai
}
  end
end
