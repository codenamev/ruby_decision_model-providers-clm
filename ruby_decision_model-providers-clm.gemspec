# frozen_string_literal: true

require_relative "lib/ruby_decision_model/providers/clm/version"

Gem::Specification.new do |spec|
  spec.name = "ruby_decision_model-providers-clm"
  spec.version = RubyDecisionModel::Providers::ClmProvider::VERSION
  spec.authors = ["Valentino Stoll"]
  spec.email = ["v@codenamev.com"]

  spec.summary = "CLM provider for ruby_decision_model: typed decisions from a Contrastive Language Model"
  spec.description = <<~DESC
    Adds a :clm provider to ruby_decision_model. By default it posts to a clm-serve
    endpoint, which speaks the same /v1/systemone API as the hosted decision models;
    given a CLM::Engine it answers in this process instead. Either way it returns
    the payload the hosted APIs return, so retries, error mapping and the typed
    answers are unchanged.
  DESC
  spec.homepage = "https://github.com/codenamev/ruby_decision_model-providers-clm"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb"] + %w[README.md CHANGELOG.md LICENSE.txt]
  spec.require_paths = ["lib"]

  spec.add_dependency "ruby-clm", ">= 0.1"
  spec.add_dependency "ruby_decision_model", ">= 0.1"
end
