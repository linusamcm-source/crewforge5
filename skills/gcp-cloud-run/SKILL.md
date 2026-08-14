---
name: gcp-cloud-run
model: sonnet
description: "Specialized skill for building production-ready serverless applications on GCP. Covers Cloud Run services (containerized), Cloud Run Functions (event-driven), cold start optimization, and event-driven architecture with Pub/Sub."
source: vibeship-spawner-skills (Apache 2.0)
---

# GCP Cloud Run

## Patterns

Each pattern is a full copy-paste template (Dockerfile / handler code / gcloud deploy). Load the matching reference on demand:

- **Cloud Run Service** — if building a containerized web service or API (any runtime/library, multiple endpoints, stateless workloads; Dockerfile + Express + cloudbuild.yaml): load [references/pattern-cloud-run-service.md](references/pattern-cloud-run-service.md)
- **Cloud Run Functions / Pub/Sub** — if writing event-driven functions (HTTP webhooks, Pub/Sub message processing, Cloud Storage triggers) or their `gcloud functions deploy` commands: load [references/pattern-event-driven-pubsub.md](references/pattern-event-driven-pubsub.md)
- **Cold Start Optimization** — if tuning latency-sensitive or user-facing services (startup CPU boost, min instances, distroless images, lazy init, memory/CPU sizing): load [references/pattern-cold-start.md](references/pattern-cold-start.md)

## Anti-Patterns

### ❌ CPU-Intensive Work Without Concurrency=1

**Why bad**: CPU is shared across concurrent requests. CPU-bound work
will starve other requests, causing timeouts.

### ❌ Writing Large Files to /tmp

**Why bad**: /tmp is an in-memory filesystem. Large files consume
your memory allocation and can cause OOM errors.

### ❌ Long-Running Background Tasks

**Why bad**: Cloud Run throttles CPU to near-zero when not handling
requests. Background tasks will be extremely slow or stall.

## ⚠️ Sharp Edges

| Issue | Severity | Solution |
|-------|----------|----------|
| /tmp counts against the memory allocation (in-memory filesystem) | high | Calculate memory including /tmp usage |
| Concurrent requests share one instance's CPU | high | Set appropriate concurrency |
| CPU throttled to near-zero outside request handling | high | Enable CPU always allocated |
| Idle connections dropped between requests | medium | Configure connection pool with keep-alive |
| Cold start latency on new instances | high | Enable startup CPU boost (`--cpu-boost`) |
| Gen1 vs gen2 execution environments behave differently | medium | Explicitly set execution environment |
| Mismatched timeouts across service, client, and dependencies | medium | Set consistent timeouts |
