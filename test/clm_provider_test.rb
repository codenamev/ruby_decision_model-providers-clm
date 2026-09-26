# frozen_string_literal: true

require "test_helper"

class CLMProviderTest < Minitest::Test
  Provider = RubyDecisionModel::Providers::CLM

  def questions
    { "urgent" => RubyDecisionModel::Questions.noul("Is this urgent?") }
  end

  def triage
    {
      "urgent" => RubyDecisionModel::Questions.noul("Is this urgent?"),
      "team" => RubyDecisionModel::Questions.choice("Which team?",
                                                    criteria: { billing: "invoices", technical: "outages" }),
      "severity" => RubyDecisionModel::Questions.score("How severe?", criteria: %w[low medium high])
    }
  end

  # --- registration

  def test_requiring_the_gem_registers_the_provider
    assert RubyDecisionModel::Providers.registered?(:clm)
    assert_instance_of Provider, RubyDecisionModel::Providers.build(:clm)
  end

  def test_it_needs_no_key_and_is_never_the_silent_default
    refute_predicate Provider.new, :requires_api_key?
    refute_includes RubyDecisionModel::Providers.env_vars, "CLM_API_KEY"
  end

  # --- over HTTP, to clm-serve

  def test_by_default_it_posts_to_clm_serve
    transport = FakeTransport.new
    RubyDecisionModel::Client.new(provider: :clm, transport: transport).ask(state: "the site is down",
                                                                          questions: questions)
    request = transport.calls.first

    assert_equal "http://127.0.0.1:8700/v1/systemone", request[:url]
    assert_equal({ "model" => "clm-latest", "state" => "the site is down", "questions" => questions }, request[:body])
    refute request[:headers].key?("Authorization"), "a keyless clm-serve would read an empty Bearer as a bad key"
  end

  def test_a_key_and_base_url_are_sent_when_given
    transport = FakeTransport.new
    RubyDecisionModel::Client.new(provider: :clm, api_key: "sekrit", base_url: "http://gpu-box:8700/",
                                  transport: transport).ask(state: "x", questions: questions)

    assert_equal "http://gpu-box:8700/v1/systemone", transport.calls.first[:url]
    assert_equal "Bearer sekrit", transport.calls.first[:headers]["Authorization"]
  end

  def test_clm_serve_answers_come_back_typed
    server = CLM::Server.new(CLM::MockEngine.new, ui: false)
    response = RubyDecisionModel::Client.new(provider: :clm, transport: RackTransport.new(server))
                                        .ask(state: "My invoice was charged twice", questions: triage)

    assert_equal "clm-latest", response.model
    assert_includes 0.0..1.0, response["urgent"].probability
    assert_includes %w[billing technical], response["team"].choice
    assert_equal({ "0" => "low", "1" => "medium", "2" => "high" }, response["severity"].legend)
    assert_equal 3, response["severity"].probabilities.size
    assert_operator response.usage.input_tokens, :>, 0
  end

  def test_clm_serve_errors_raise_the_usual_errors
    server = CLM::Server.new(CLM::MockEngine.new, api_key: "right", ui: false)
    client = RubyDecisionModel::Client.new(provider: :clm, api_key: "wrong", transport: RackTransport.new(server),
                                           retry: { max_retries: 0 })

    assert_raises(RubyDecisionModel::Unauthorized) { client.ask(state: "x", questions: questions) }
  end

  # --- in this process

  def test_a_client_answers_here_instead
    fake = FakeCLM.new
    response = RubyDecisionModel::Client.new(provider: Provider.new(client: fake))
                                        .ask(state: { "body" => "the site is down" }, questions: questions)

    assert_in_delta 0.82, response["urgent"].probability, 1e-9
    assert_equal 38, response.usage.input_tokens
    assert_nil response.usage.cost, "a local model has no per-call cost"
    assert_equal [{ state: { "body" => "the site is down" }, questions: questions, options: { model: "clm-latest" } }],
                 fake.calls
  end

  def test_a_model_name_selects_the_served_head
    fake = FakeCLM.new
    RubyDecisionModel::Client.new(provider: Provider.new(client: fake), model: "raw")
                             .ask(state: "x", questions: questions)

    assert_equal({ model: "clm-raw" }, fake.calls.first[:options])
  end

  def test_the_engine_answers_every_question_type
    engine = CLM::MockEngine.new
    response = RubyDecisionModel::Client.new(provider: Provider.new(client: engine))
                                        .ask(state: "My invoice was charged twice", questions: triage)

    assert_equal %w[noul choice score], %w[urgent team severity].map { response[_1].type }
    assert_equal "billing", response["team"].choice
    assert_in_delta 1.0, response["team"].probabilities.values.sum, 1e-9
  end

  def test_engine_errors_become_the_statuses_clm_serve_answers_with
    unknown = Provider.new(client: FakeCLM.new(raises: CLM::ModelNotFoundError.new("unknown model \"gpt\"")))
    assert_raises(RubyDecisionModel::UnprocessableEntity) do
      RubyDecisionModel::Client.new(provider: unknown).ask(state: "x", questions: questions)
    end

    down = Provider.new(client: FakeCLM.new(raises: CLM::EmbedderError.new("embedder unreachable")))
    error = assert_raises(RubyDecisionModel::ApiError) do
      RubyDecisionModel::Client.new(provider: down, retry: { max_retries: 0 }).ask(state: "x", questions: questions)
    end
    assert_equal 502, error.status
  end

  def test_local_builds_an_engine_once_and_only_when_asked
    provider = Provider.new(local: true, action_cache: 0,
                            config: CLM::Configuration.new("CLM_CKPT_DIR" => File::NULL))

    assert_match(/local loaded=false/, provider.inspect)
    assert_instance_of CLM::Engine, provider.client
    assert_same provider.client, provider.client
    assert_match(/local loaded=true/, provider.inspect)
    assert_nil Provider.new.client, "over HTTP there is no model to build"
  end

  def test_aliases_resolve_to_served_models
    provider = Provider.new

    assert_equal "clm-latest", provider.resolve_model(nil)
    assert_equal "clm-latest", provider.resolve_model("clm")
    assert_equal "clm-latest", provider.resolve_model("Contrastive-LM/CLM-v0.1-8B")
    assert_equal "clm-raw", provider.resolve_model("raw")
    assert_equal "my-head", provider.resolve_model("my-head"), "an unknown name passes through"
  end

  def test_an_injected_transport_still_wins
    transport = FakeTransport.new
    response = RubyDecisionModel::Client.new(provider: Provider.new(client: FakeCLM.new), transport: transport)
                                        .ask(state: "x", questions: questions)

    assert_in_delta 0.1, response["urgent"].probability, 1e-9
    assert_equal 1, transport.calls.length
  end

  def test_inspect_keeps_the_key_out
    refute_match(/sekrit/, Provider.new(api_key: "sekrit").inspect)
  end
end
