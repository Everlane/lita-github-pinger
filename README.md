# lita-github-pinger

This is a Lita handler for pinging you about github events that you should know about.

In particular, it will ping you under four circumstances (right now):

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

You will need to have a config variable named `config.handlers.github_pinger.engineers` set to the following:

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
    travis_preferences: { # I know, not everybody uses travis - this will still work.
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
