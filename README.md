# lita-github-pinger

This is a Lita handler for pinging you about github events that you should know about.

In particular, it can ping you under four circumstances (right now):

1. Somebody has commented on your pull request
2. Somebody has @mentioned you through a comment on a pull request
3. Somebody has assigned you to a pull request
4. The status of your pull request was set to "failing"

## Installation

Add lita-github-pinger to your Lita instance's Gemfile:

``` ruby
gem "lita-github-pinger"
```

## Configuration

For any repos which you would like to watch, add a GitHub webhook that will post to http://yourlitaapp.herokuapp.com/ghping and check off the following events:

- Issue comment
- Pull Request review comment
- Pull Request
- Status


You will also need to have a config variable named `config.handlers.github_pinger.engineers` set to the following:

```ruby
config.handlers.github_pinger.engineers = {
  "Your Name" => {
    usernames: {
      slack: "yourname", # I know, not everybody uses slack - this will still work.
      github: "awesome"
    },
    github_preferences: {
      frequency: "all_discussion",
      location: "dm"
    },
    status_preferences: {
      frequency: "only_failures"
    }
  },
  "Another Name" => {
    # ...
  }
}
```

## Usage

There is no interface, Lita does all the talking here.
