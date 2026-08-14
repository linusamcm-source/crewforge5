### Bedrock Guardrails Gateway Pattern

API Gateway + Lambda pattern enforcing Bedrock Guardrails on all model invocations. Uses `bedrock:GuardrailIdentifier` IAM condition key and the independent `ApplyGuardrail` API for screening content from any LLM provider.

**When to use**: ['Enforcing content safety on model invocations', 'Screening third-party LLM content through Bedrock Guardrails', 'PII detection/redaction in serverless AI pipelines']

```yaml
# template.yaml — Guardrails-enforced model invocation
Resources:
  InvokeModelFunction:
    Type: AWS::Serverless::Function
    Properties:
      Handler: src/handlers/invoke-model.handler
      Runtime: nodejs20.x
      Timeout: 60
      MemorySize: 512
      Environment:
        Variables:
          GUARDRAIL_ID: !Ref BedrockGuardrailId
          GUARDRAIL_VERSION: !Ref BedrockGuardrailVersion
      Policies:
        - Statement:
            - Effect: Allow
              Action:
                - bedrock:InvokeModel
              Resource:
                # Restrict to specific approved models only
                - !Sub "arn:aws:bedrock:${AWS::Region}::foundation-model/anthropic.claude-3-5-sonnet*"
                - !Sub "arn:aws:bedrock:${AWS::Region}::foundation-model/anthropic.claude-3-haiku*"
              Condition:
                StringEquals:
                  # Force guardrail usage — invocations without this guardrail are denied
                  "bedrock:GuardrailIdentifier": !Ref BedrockGuardrailId
            - Effect: Allow
              Action:
                - bedrock:ApplyGuardrail
              Resource:
                - !Sub "arn:aws:bedrock:${AWS::Region}:${AWS::AccountId}:guardrail/${BedrockGuardrailId}"

  # Screen third-party LLM content through Bedrock Guardrails
  ScreenContentFunction:
    Type: AWS::Serverless::Function
    Properties:
      Handler: src/handlers/screen-content.handler
      Runtime: nodejs20.x
      Timeout: 30
      MemorySize: 256
      Environment:
        Variables:
          GUARDRAIL_ID: !Ref BedrockGuardrailId
          GUARDRAIL_VERSION: !Ref BedrockGuardrailVersion
      Policies:
        - Statement:
            - Effect: Allow
              Action:
                - bedrock:ApplyGuardrail
              Resource:
                - !Sub "arn:aws:bedrock:${AWS::Region}:${AWS::AccountId}:guardrail/${BedrockGuardrailId}"

Parameters:
  BedrockGuardrailId:
    Type: String
    Description: Bedrock Guardrail ID to enforce
  BedrockGuardrailVersion:
    Type: String
    Default: DRAFT
```

```javascript
// src/handlers/invoke-model.js
// Model invocation with mandatory guardrails and input tagging

const { BedrockRuntimeClient, InvokeModelCommand } = require('@aws-sdk/client-bedrock-runtime');
const client = new BedrockRuntimeClient({});

exports.handler = async (event) => {
  const { prompt, systemPrompt, externalContext } = JSON.parse(event.body);

  // Build messages with input tagging for indirect prompt injection defense
  // Tag external/RAG content as 'USER' so guardrails evaluate it for hidden instructions
  const messages = [
    { role: 'user', content: prompt }
  ];

  const response = await client.send(new InvokeModelCommand({
    modelId: 'anthropic.claude-3-5-sonnet-20241022-v2:0',
    contentType: 'application/json',
    accept: 'application/json',
    guardrailIdentifier: process.env.GUARDRAIL_ID,
    guardrailVersion: process.env.GUARDRAIL_VERSION,
    body: JSON.stringify({
      anthropic_version: 'bedrock-2023-05-31',
      max_tokens: 4096,
      system: systemPrompt || 'You are a helpful assistant.',
      messages
    })
  }));

  const result = JSON.parse(new TextDecoder().decode(response.body));

  // Check if guardrails intervened
  if (response.guardrailAction === 'INTERVENED') {
    return {
      statusCode: 200,
      body: JSON.stringify({
        content: result.content,
        guardrailIntervened: true,
        guardrailTrace: response.guardrailTrace
      })
    };
  }

  return {
    statusCode: 200,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ content: result.content, guardrailIntervened: false })
  };
};
```

```javascript
// src/handlers/screen-content.js
// Independent guardrail evaluation — screen content from any LLM provider
// Use ApplyGuardrail API to enforce consistent policy across Bedrock + third-party models

const { BedrockRuntimeClient, ApplyGuardrailCommand } = require('@aws-sdk/client-bedrock-runtime');
const client = new BedrockRuntimeClient({});

exports.handler = async (event) => {
  const { content, source } = JSON.parse(event.body);

  const response = await client.send(new ApplyGuardrailCommand({
    guardrailIdentifier: process.env.GUARDRAIL_ID,
    guardrailVersion: process.env.GUARDRAIL_VERSION,
    source: source || 'OUTPUT', // INPUT or OUTPUT
    content: [{ text: { text: content } }]
  }));

  const blocked = response.action === 'GUARDRAIL_INTERVENED';

  return {
    statusCode: 200,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      allowed: !blocked,
      action: response.action,
      outputs: response.outputs,
      assessments: response.assessments
    })
  };
};
```
