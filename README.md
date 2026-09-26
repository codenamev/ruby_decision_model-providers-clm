# ruby_decision_model-providers-clm

The `:clm` provider for [ruby_decision_model](https://github.com/obie/ruby_decision_model).

[CLM](https://github.com/Contrastive-LM/CLM), a Contrastive Language Model, answers typed questions
by scoring each candidate answer against the state: a frozen Qwen3-8B encoder, two small trained
projection heads, and a softmax over their cosine similarities. Its server, `clm-serve`, speaks the
same `POST /v1/systemone` API as the hosted decision models, so this provider is mostly a pointer to
it. Given a model of your own, it answers in your process instead, through
[ruby-clm](https://github.com/codenamev/ruby-clm).

Either way it returns the payload the hosted APIs return, so retries, error mapping and the typed
answers are the same code you already use.

## Install

This gem is not on RubyGems yet: it depends on a registration hook that is still a pull request
against ruby_decision_model, and on ruby-clm, which is not released either. Until they land, point
Bundler at checkouts:

```ruby
gem "ruby_decision_model", github: "obie/ruby_decision_model", branch: "main"
gem "ruby-clm", github: "codenamev/ruby-clm", require: "clm"
gem "ruby_decision_model-providers-clm",
    github: "codenamev/ruby_decision_model-providers-clm",
    require: "ruby_decision_model/providers/clm"
```

Or, working on them side by side:

```ruby
gem "ruby_decision_model", path: "../ruby_decision_model"
gem "ruby-clm", path: "../ruby-clm", require: "clm"
gem "ruby_decision_model-providers-clm",
    path: "../ruby_decision_model-providers-clm",
    require: "ruby_decision_model/providers/clm"
```

Once they are released it is the usual one line:

```ruby
gem "ruby_decision_model-providers-clm", require: "ruby_decision_model/providers/clm"
```

Requiring it registers the provider. Ruby 3.2 or newer. Over HTTP it loads nothing beyond the
standard library; the in-process engine brings Numo and loads it only when it is built.

## Use

Start `clm-serve` (see the [ruby-clm README](https://github.com/codenamev/ruby-clm#serve): a Qwen3-8B
pooling server on a GPU, and the 72 MB head), then:

```ruby
client = RubyDecisionModel::Client.new(provider: :clm) # http://127.0.0.1:8700, or CLM_BASE_URL

response = client.ask(
  state: { from: "ap@acme.com", subject: "Duplicate charge on invoice #4411",
           body: "We were billed twice for March. Please refund the duplicate today." },
  questions: {
    "team" => RubyDecisionModel::Questions.choice(
      "Which team should handle this?",
      criteria: { billing: "invoices, payments, refunds", technical: "bugs, outages" }
    ),
    "urgent" => RubyDecisionModel::Questions.noul("Is this urgent?"),
    "severity" => RubyDecisionModel::Questions.score("How severe is this?", criteria: %w[low medium high])
  }
)

response["team"].choice        # => "billing"
response["urgent"].probability # the probability the statement holds
response["severity"].score     # the expected level, 0..2
response.usage.input_tokens    # encoder tokens spent on texts clm-serve had not cached
response.usage.cost            # => nil, nothing was billed
```

A server elsewhere, or one started with `CLM_API_KEY`:

```ruby
RubyDecisionModel::Client.new(provider: :clm, base_url: "http://gpu-box:8700", api_key: ENV["CLM_API_KEY"])
```

No key, no `Authorization` header: a keyless `clm-serve` ignores it, and one with a key answers 401,
which raises `RubyDecisionModel::Unauthorized` as it would for any provider.

## Choosing a model

`clm-serve` serves every head it was started with, listed by `GET /v1/models`:

| You pass | Answers with |
| --- | --- |
| `nil`, `"clm"`, `"Contrastive-LM/CLM-v0.1-8B"` | `clm-latest`, the reference head |
| `"clm-raw"`, `"raw"` | cosine in the encoder's own space, no head (an ablation) |
| any other name | that head, e.g. one served with `clm-serve --model triage=runs/triage.pt` |

```ruby
RubyDecisionModel::Client.new(provider: :clm, model: "triage")
```

## Answering in this process

Pass a model and requests never leave the process: no `clm-serve`, just the encoder the engine
embeds with. Anything answering `predict(state, questions, model:)` works, which is how you hand
over an engine your application already has:

```ruby
engine = CLM::Engine.new(checkpoint: CLM::Hub.download)
RubyDecisionModel::Client.new(provider: RubyDecisionModel::Providers::CLM.new(client: engine))
```

Or let the provider build one on first use, passing any other keyword to `CLM::Engine`:

```ruby
RubyDecisionModel::Providers.build(:clm, local: true, action_cache: "512MiB")
```

The engine's own failures become the statuses `clm-serve` would have answered with: an unknown model
or malformed question raises `RubyDecisionModel::UnprocessableEntity`, and an unreachable encoder a
502 `RubyDecisionModel::ApiError`, retried like any other.

## What it is good at, and what it is not

The CLM authors report that CLM-8B performs on par with Jev across computer-use, gaming and
tool-calling tasks with up to 9× lower latency, and that fine-tuned heads set state-of-the-art
verifier results on Terminal-Bench 2.1 and DeepSWE. Those are their measurements, in the
[CLM README](https://github.com/Contrastive-LM/CLM#results); this gem has not re-run them. What is
structural: it needs a GPU for its encoder, where Laya runs on a CPU; answers for a repeated state or
candidate come from a cache instead of the encoder; and a state longer than the encoder's context
(2048 tokens by default) is truncated.

## Development

```bash
bundle install
bundle exec rake test   # doubles and the mock engine stand in for the model; no GPU needed
```

The tests drive a real `CLM::Server` through ruby_decision_model's own client, over a Rack transport
instead of a socket, so the wire format is checked end to end.

## License

MIT. CLM was developed by the Contrastive-LM authors and is Apache 2.0, as are the CLM-8B weights.
