---
name: aws-serverless
model: sonnet
description: "Specialized skill for building production-ready serverless applications on AWS. Covers Lambda functions, API Gateway, DynamoDB, SQS/SNS event-driven patterns, SAM/CDK deployment, cold start optimization, and Bedrock AI integration security (Agents, Guardrails, Knowledge Bases)."
source: vibeship-spawner-skills (Apache 2.0)
---

# AWS Serverless

## Patterns

Each pattern is a full copy-paste template (SAM template.yaml + handler code). Load the matching reference on demand:

- **Lambda Handler** — if implementing any Lambda function (API handlers, event processors, scheduled tasks; Node.js + Python): load [references/pattern-lambda-handler.md](references/pattern-lambda-handler.md)
- **API Gateway Integration** — if building REST/HTTP API endpoints backed by Lambda: load [references/pattern-api-gateway.md](references/pattern-api-gateway.md)
- **Event-Driven SQS** — if doing decoupled async processing with retries, DLQ, or batch failure handling: load [references/pattern-event-driven-sqs.md](references/pattern-event-driven-sqs.md)
- **Bedrock Agent Action Group Lambda** — if writing Lambdas invoked by Bedrock Agents (confused deputy prevention, least-privilege roles): load [references/pattern-bedrock-agent-action-group.md](references/pattern-bedrock-agent-action-group.md)
- **Bedrock Guardrails Gateway** — if enforcing guardrails on model invocations, screening third-party LLM content via ApplyGuardrail, or PII detection/redaction: load [references/pattern-bedrock-guardrails-gateway.md](references/pattern-bedrock-guardrails-gateway.md)
- **Security Monitoring Pipeline** — if building GuardDuty/EventBridge/Lambda triage and audit for Bedrock workloads: load [references/pattern-security-monitoring-pipeline.md](references/pattern-security-monitoring-pipeline.md)
- **Bedrock IAM Least Privilege** — if scoping IAM policies to specific Bedrock models/actions, SCPs, or guardrail-enforcing conditions: load [references/pattern-bedrock-iam-least-privilege.md](references/pattern-bedrock-iam-least-privilege.md)

## Anti-Patterns

### ❌ Monolithic Lambda

**Why bad**: Large deployment packages cause slow cold starts.
Hard to scale individual operations.
Updates affect entire system.

### ❌ Large Dependencies

**Why bad**: Increases deployment package size.
Slows down cold starts significantly.
Most of SDK/library may be unused.

### ❌ Synchronous Calls in VPC

**Why bad**: VPC-attached Lambdas have ENI setup overhead.
Blocking DNS lookups or connections worsen cold starts.

### ❌ Overly Broad Bedrock IAM (`bedrock:*`)

**Why bad**: Grants access to all models (including expensive/inappropriate ones), agent management, guardrail deletion, and model customization. Any compromised Lambda can invoke any model, modify guardrails, or exfiltrate training data. Always restrict to specific model ARNs and actions.

### ❌ Missing Confused Deputy Prevention on Agent Lambdas

**Why bad**: Without `aws:SourceAccount` and `aws:SourceArn` conditions on Lambda resource-based policies, any Bedrock account/agent can invoke your Lambda. An attacker with a Bedrock agent in their own account could call your action group Lambda directly.

### ❌ No Guardrail Enforcement in IAM Policies

**Why bad**: Without the `bedrock:GuardrailIdentifier` condition key, model invocations can bypass content safety filters. A developer or compromised credential can call `InvokeModel` without guardrails. Use IAM conditions to make guardrails mandatory, not optional.

### ❌ Trusting RAG Content as System Input

**Why bad**: Retrieved documents from Knowledge Bases may contain adversarial instructions (indirect prompt injection). If RAG content is treated as trusted system context, hidden commands in documents can manipulate agent behavior. Always tag retrieved content as `USER` input source so guardrails evaluate it.

## ⚠️ Sharp Edges

| Issue | Severity | Solution |
|-------|----------|----------|
| Cold start latency spikes | high | Measure INIT phase; use provisioned concurrency for latency-sensitive paths |
| Lambda timeout misconfig | high | Set timeout to match actual workload; SQS visibility timeout should be 6x Lambda timeout |
| Memory-bound CPU throttling | high | Increase memory allocation — CPU scales linearly with memory in Lambda |
| VPC cold starts add 1-10s | medium | Use VPC only when required; use PrivateLink for Bedrock API access |
| Node.js event loop keeps Lambda alive | medium | Set `context.callbackWaitsForEmptyEventLoop = false` |
| S3 trigger infinite loops | high | Use separate input/output buckets or distinct prefixes |
| Large file uploads timeout at API Gateway | medium | Use pre-signed S3 URLs for uploads > 10MB |
| Bedrock model invocation without guardrails | high | Enforce `bedrock:GuardrailIdentifier` in IAM conditions |
| Agent Lambda missing source conditions | high | Add `aws:SourceAccount` + `aws:SourceArn` to resource-based policies |
| Bedrock API calls over public internet | medium | Configure VPC endpoints with PrivateLink for Bedrock |
| GuardDuty Bedrock alerts ignored | medium | Route to EventBridge with automated triage Lambda |
| Denial-of-wallet via model abuse | high | Set AWS Budgets alerts; restrict `InvokeModel` to specific principals/VPCs; implement app-level rate limiting |
| RAG content treated as trusted | high | Tag all external/RAG content as `USER` input source for guardrail evaluation |
| Model invocation logging disabled | medium | Enable opt-in model invocation logging in Bedrock Settings for audit trail |
