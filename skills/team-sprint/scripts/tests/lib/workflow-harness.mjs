// workflow-harness.mjs — run a *.workflow.js under stubs, without spawning agents.
//
// Workflow scripts execute inside the Workflow tool, which supplies the globals
// agent/parallel/pipeline/phase/log/budget/args. `node --check` only proves the
// file parses — it proved nothing about the args-as-string bug that made both
// workflows unlaunchable. This harness actually RUNS the script body with those
// globals stubbed, so a smoke test can assert real behaviour: the required-args
// guard, loop bounds, which agents get spawned, and what the prompts contain.
//
// Usage:
//   node workflow-harness.mjs <workflow.js> <args-json> [<responses-json>]
//
// <args-json>      passed through as the `args` global VERBATIM — pass a JSON
//                  string to reproduce the stringified-args path.
// <responses-json> optional {labelPrefix: value} map; the agent() stub returns
//                  the first value whose key prefixes the call's label.
//
// Emits one JSON object on stdout:
//   {ok, result?, error?, calls:[{label,phase,agentType,model,prompt}], logs:[]}

import { readFileSync } from 'node:fs'

const [, , wfPath, argsRaw, responsesRaw] = process.argv
if (!wfPath) {
  console.error('usage: workflow-harness.mjs <workflow.js> <args-json> [<responses-json>]')
  process.exit(2)
}

let argsValue
try {
  argsValue = argsRaw === undefined || argsRaw === '' ? undefined : JSON.parse(argsRaw)
} catch {
  argsValue = argsRaw // a deliberately-malformed string; hand it over raw
}
// A JSON string arg is expressed as a JSON-encoded string, e.g. "\"{...}\"" —
// JSON.parse yields the inner string, which is exactly the harness shape we
// need to reproduce.

const responses = responsesRaw ? JSON.parse(responsesRaw) : {}

const calls = []
const logs = []

function pick(label) {
  for (const k of Object.keys(responses)) {
    if (label && label.startsWith(k)) return responses[k]
  }
  return null
}

async function agent(prompt, opts = {}) {
  const label = opts.label || '(unlabelled)'
  calls.push({
    label,
    phase: opts.phase || null,
    agentType: opts.agentType || null,
    model: opts.model || null,
    hasSchema: !!opts.schema,
    prompt: String(prompt),
  })
  return pick(label)
}

async function parallel(thunks) {
  const out = []
  for (const t of thunks) {
    try { out.push(await t()) } catch { out.push(null) }
  }
  return out
}

async function pipeline(items, ...stages) {
  const out = []
  for (let i = 0; i < items.length; i += 1) {
    let v = items[i]
    try {
      for (const s of stages) v = await s(v, items[i], i)
      out.push(v)
    } catch { out.push(null) }
  }
  return out
}

const phase = () => {}
const log = (m) => logs.push(String(m))
const budget = { total: null, spent: () => 0, remaining: () => Infinity }

let src = readFileSync(wfPath, 'utf8')
// `export` is only legal in a module; the body is otherwise plain script.
src = src.replace(/^export\s+const\s+meta\s*=/m, 'const meta =')

const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor

const emit = (o) => process.stdout.write(JSON.stringify(o) + '\n')

try {
  const fn = new AsyncFunction(
    'args', 'agent', 'parallel', 'pipeline', 'phase', 'log', 'budget', src,
  )
  const result = await fn(argsValue, agent, parallel, pipeline, phase, log, budget)
  emit({ ok: true, result, calls, logs })
} catch (e) {
  emit({ ok: false, error: String((e && e.message) || e), calls, logs })
}
