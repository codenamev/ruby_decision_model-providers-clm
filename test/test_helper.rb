# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "rack"
require "ruby_decision_model/providers/clm"

# Stands in for a CLM model. The provider only ever sends it
# `predict(state, questions, model:)`, so this is the whole surface.
class FakeCLM
  attr_reader :calls

  def initialize(answers: nil, raises: nil)
    @answers = answers
    @raises = raises
    @calls = []
  end

  def predict(state, questions, **options)
    @calls << { state: state, questions: questions, options: options }
    raise @raises if @raises

    { "model" => options[:model],
      "answers" => @answers || questions.keys.to_h { |id| [id.to_s, { "type" => "noul", "noul" => 0.82 }] },
      "usage" => { "billing_units" => questions.size, "input_tokens" => 38, "output_tokens" => 0 } }
  end
end

# A transport in the shape Client expects, recording requests and replying from a queue.
class FakeTransport
  attr_reader :calls

  def initialize(reply = nil)
    @reply = reply || { "model" => "clm-latest", "answers" => { "urgent" => { "type" => "noul", "noul" => 0.1 } },
                        "usage" => { "input_tokens" => 1, "output_tokens" => 0 } }
    @calls = []
  end

  def call(url:, headers:, body:)
    @calls << { url: url, headers: headers, body: JSON.parse(body) }
    [200, JSON.generate(@reply), {}]
  end
end

# Client's transport, answered by a Rack app in this process: a real CLM::Server
# with no socket in between, so the wire format is tested end to end.
class RackTransport
  def initialize(app)
    @app = app
  end

  def call(url:, headers:, body:)
    env = Rack::MockRequest.env_for(url, method: "POST", input: body, "CONTENT_TYPE" => headers["Content-Type"],
                                         "HTTP_AUTHORIZATION" => headers["Authorization"])
    status, response_headers, chunks = @app.call(env)
    [status, chunks.to_enum(:each).to_a.join, response_headers.to_h]
  end
end
