### Security Monitoring Pipeline Pattern

EventBridge + Step Functions + Lambda pipeline for automated Bedrock security incident detection and response. GuardDuty detects anomalies, EventBridge routes findings, Lambda + Bedrock generates human-readable summaries and remediations.

**When to use**: ['Automated security monitoring for Bedrock workloads', 'GuardDuty finding triage and alerting', 'Compliance audit trails for AI workloads']

```yaml
# template.yaml — Security monitoring pipeline
Resources:
  # GuardDuty finding → EventBridge rule
  BedrockSecurityRule:
    Type: AWS::Events::Rule
    Properties:
      Description: Route Bedrock-related GuardDuty findings
      EventPattern:
        source:
          - aws.guardduty
        detail-type:
          - GuardDuty Finding
        detail:
          service:
            additionalInfo:
              # Match findings involving Bedrock API anomalies
              value:
                - prefix: "bedrock"
      State: ENABLED
      Targets:
        - Arn: !GetAtt SecurityTriageFunction.Arn
          Id: BedrockSecurityTriage

  SecurityTriageFunction:
    Type: AWS::Serverless::Function
    Properties:
      Handler: src/handlers/security-triage.handler
      Runtime: nodejs20.x
      Timeout: 60
      MemorySize: 512
      Environment:
        Variables:
          SNS_TOPIC_ARN: !Ref SecurityAlertTopic
          GUARDRAIL_ID: !Ref GuardrailId
      Policies:
        - Statement:
            - Effect: Allow
              Action:
                - bedrock:InvokeModel
              Resource:
                - !Sub "arn:aws:bedrock:${AWS::Region}::foundation-model/anthropic.claude-3-haiku*"
        - SNSPublishMessagePolicy:
            TopicName: !GetAtt SecurityAlertTopic.TopicName

  SecurityAlertTopic:
    Type: AWS::SNS::Topic
    Properties:
      TopicName: bedrock-security-alerts

  # CloudTrail for Bedrock API audit
  BedrockAuditTrail:
    Type: AWS::CloudTrail::Trail
    Properties:
      IsLogging: true
      S3BucketName: !Ref AuditBucket
      EventSelectors:
        - ReadWriteType: All
          IncludeManagementEvents: true
      InsightSelectors:
        - InsightType: ApiCallRateInsight
```

```javascript
// src/handlers/security-triage.js
// Automated triage of GuardDuty findings related to Bedrock

const { BedrockRuntimeClient, InvokeModelCommand } = require('@aws-sdk/client-bedrock-runtime');
const { SNSClient, PublishCommand } = require('@aws-sdk/client-sns');

const bedrock = new BedrockRuntimeClient({});
const sns = new SNSClient({});

// Known high-severity patterns for Bedrock
const CRITICAL_PATTERNS = [
  'guardrail removal',
  'training data bucket change',
  'model access policy change',
  'unusual invocation volume'
];

exports.handler = async (event) => {
  const finding = event.detail;
  const severity = finding.severity;

  // Classify finding severity
  const isCritical = severity >= 7 || CRITICAL_PATTERNS.some(
    p => JSON.stringify(finding).toLowerCase().includes(p)
  );

  // Use Bedrock to generate human-readable summary
  const summary = await generateFindingSummary(finding);

  // Publish alert
  await sns.send(new PublishCommand({
    TopicArn: process.env.SNS_TOPIC_ARN,
    Subject: `[${isCritical ? 'CRITICAL' : 'WARNING'}] Bedrock Security Finding`,
    Message: JSON.stringify({
      severity: isCritical ? 'CRITICAL' : 'WARNING',
      findingId: finding.id,
      findingType: finding.type,
      summary,
      timestamp: new Date().toISOString(),
      remediation: summary.remediation
    }, null, 2)
  }));

  return { statusCode: 200, processed: true };
};

async function generateFindingSummary(finding) {
  const response = await bedrock.send(new InvokeModelCommand({
    modelId: 'anthropic.claude-3-haiku-20240307-v1:0',
    contentType: 'application/json',
    accept: 'application/json',
    body: JSON.stringify({
      anthropic_version: 'bedrock-2023-05-31',
      max_tokens: 1024,
      system: 'You are a security analyst. Summarize the GuardDuty finding and provide remediation steps. Be concise.',
      messages: [{
        role: 'user',
        content: `Analyze this GuardDuty finding:\n${JSON.stringify(finding, null, 2)}`
      }]
    })
  }));

  const result = JSON.parse(new TextDecoder().decode(response.body));
  return result.content[0].text;
}
```
