# frozen_string_literal: true

require "json"
require "clm" # cheap: the engine's Numo, rubyzip and Async load only when it is built
require "ruby_decision_model"
require_relative "clm/version"

# The provider class and its version live in the same gem; the version is in its
# own namespace so the gemspec can read it on its own.

module RubyDecisionModel
  module Providers
    # CLM, a Contrastive Language Model, served by clm-serve or run in this process.
    #
    # clm-serve speaks the same POST /v1/systemone API as the hosted decision
    # models, so by default this provider is an ordinary HTTP one pointed at it:
    #
    #   client = RubyDecisionModel::Client.new(provider: :clm)   # http://127.0.0.1:8700
    #   client = RubyDecisionModel::Client.new(provider: :clm, base_url: "http://gpu-box:8700")
    #
    # Given a model to answer with, it answers in this process instead, through
    # the same transport seam, so retries, error mapping and the typed answers
    # are the same code:
    #
    #   provider = RubyDecisionModel::Providers::CLM.new(client: CLM::Engine.new)
    #   provider = RubyDecisionModel::Providers.build(:clm, local: true)  # builds the engine on first use
    #   RubyDecisionModel::Client.new(provider: provider).ask(state: ticket, questions: questions)
    class CLM < Base
      LATEST = "clm-latest"

      ALIASES = {
        "clm" => LATEST,
        "Contrastive-LM/CLM-v0.1-8B" => LATEST,
        "CLM-v0.1-8B" => LATEST,
        "raw" => "clm-raw"
      }.freeze

      # `client` is anything answering `predict(state, questions, model:)`: a
      # ::CLM::Engine, a ::CLM::Client, or a double. `local: true` builds a
      # ::CLM::Engine on first use, passing it any other keyword (checkpoint:,
      # action_cache:, embedder:, ...). Neither means clm-serve over HTTP.
      def initialize(api_key: nil, base_url: nil, client: nil, local: false, **engine_options)
        super(api_key: api_key, base_url: base_url)
        @client = client
        @local = local || !client.nil?
        @engine_options = engine_options
      end

      def name = :clm

      # clm-serve requires a key only when it was started with CLM_API_KEY set.
      def env_var = "CLM_API_KEY"
      def requires_api_key? = false

      def default_base_url = ENV.fetch("CLM_BASE_URL", "http://127.0.0.1:8700")
      def endpoint_path = "/v1/systemone"
      def default_model = LATEST
      def aliases = ALIASES

      # Whether requests are answered in this process rather than by clm-serve.
      def local? = @local

      # No key, no Authorization header: a keyless clm-serve would take "Bearer " as a bad key.
      def headers
        api_key? ? super : super.except("Authorization")
      end

      # Nil sends requests to clm-serve over Client's HTTP transport. Local, it
      # answers them here, in the shape Client's transport takes, so nothing
      # downstream needs a special case.
      def transport
        return unless local?

        lambda do |url:, headers:, body:| # rubocop:disable Lint/UnusedBlockArgument
          answer(JSON.parse(body))
        end
      end

      # The model answering locally, built on first use and reused, so a
      # long-lived Client keeps the heads resident.
      def client
        @client ||= build_client if local?
      end

      def inspect
        where = local? ? "local loaded=#{!@client.nil?}" : "base_url=#{base_url.inspect}"
        "#<#{self.class.name} name=:clm #{where} api_key=#{api_key? ? "[REDACTED]" : "nil"}>"
      end

      private

      # The engine's own failures become the statuses clm-serve would have
      # answered with, so Client raises the errors it would for the server.
      def answer(request)
        result = client.predict(request["state"], request["questions"], model: request["model"])
        [200, JSON.generate(result.respond_to?(:to_h) ? result.to_h : result), {}]
      rescue ArgumentError => e
        [422, JSON.generate("detail" => e.message), {}]
      rescue ::CLM::EmbedderError => e
        [502, JSON.generate("detail" => e.message), {}]
      end

      def build_client
        ::CLM::Engine.new(**@engine_options)
      end
    end
  end
end

RubyDecisionModel::Providers.register(:clm, RubyDecisionModel::Providers::CLM)
