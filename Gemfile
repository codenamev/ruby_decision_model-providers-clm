# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# Until the registration hook is released upstream (obie/ruby_decision_model#21), and ruby-clm is on
# RubyGems: checkouts beside this one when they are there, as when working on them together, and
# the branches that carry the work otherwise, as in CI.
def sibling(name) = File.expand_path("../#{name}", __dir__)

if File.directory?(sibling("ruby_decision_model"))
  gem "ruby_decision_model", path: sibling("ruby_decision_model")
else
  gem "ruby_decision_model", github: "codenamev/ruby_decision_model", branch: "laya-provider"
end

if File.directory?(sibling("ruby-clm"))
  gem "ruby-clm", path: sibling("ruby-clm")
else
  gem "ruby-clm", github: "codenamev/ruby-clm", branch: "main"
end

gem "minitest", "~> 5.0"
gem "rack", "~> 3.0" # the end-to-end test serves a real CLM::Server
gem "rake", "~> 13.0"
