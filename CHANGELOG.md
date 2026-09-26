# Changelog

## 0.1.0

First release.

- Adds the `:clm` provider to ruby_decision_model. By default it posts to `clm-serve`
  (`http://127.0.0.1:8700`, or `CLM_BASE_URL`), which speaks the hosted APIs' `/v1/systemone`,
  sending `CLM_API_KEY` only when one is set.
- Answers in this process instead when given `client:` (a `CLM::Engine`, or anything answering
  `predict`) or `local: true`, mapping the engine's failures to the statuses `clm-serve` returns.
- `clm`, `Contrastive-LM/CLM-v0.1-8B` and `CLM-v0.1-8B` alias `clm-latest`; `raw` aliases `clm-raw`.
