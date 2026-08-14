### Bedrock IAM Least Privilege Pattern

IAM policies scoped to specific models, actions, and guardrail enforcement for Bedrock workloads. Prevents overly broad access and enforces defense-in-depth.

**When to use**: ['Any serverless app invoking Bedrock models', 'Multi-account Bedrock deployments with SCPs', 'Enforcing guardrail usage via IAM conditions']

```yaml
# IAM policy examples for Bedrock least privilege

# 1. Model invocation — specific models only, guardrails required
InvokeModelPolicy:
  Type: AWS::IAM::ManagedPolicy
  Properties:
    PolicyDocument:
      Version: '2012-10-17'
      Statement:
        - Sid: AllowSpecificModelsWithGuardrails
          Effect: Allow
          Action:
            - bedrock:InvokeModel
            - bedrock:InvokeModelWithResponseStream
          Resource:
            - !Sub "arn:aws:bedrock:${AWS::Region}::foundation-model/anthropic.claude-3-5-sonnet*"
            - !Sub "arn:aws:bedrock:${AWS::Region}::foundation-model/anthropic.claude-3-haiku*"
          Condition:
            StringEquals:
              bedrock:GuardrailIdentifier: !Ref GuardrailId

        # Deny all models not explicitly listed (defense-in-depth)
        - Sid: DenyUnauthorizedModels
          Effect: Deny
          Action:
            - bedrock:InvokeModel
            - bedrock:InvokeModelWithResponseStream
          NotResource:
            - !Sub "arn:aws:bedrock:${AWS::Region}::foundation-model/anthropic.claude-3-5-sonnet*"
            - !Sub "arn:aws:bedrock:${AWS::Region}::foundation-model/anthropic.claude-3-haiku*"

# 2. Knowledge Base — read-only retrieval, no management
KnowledgeBaseRetrievePolicy:
  Type: AWS::IAM::ManagedPolicy
  Properties:
    PolicyDocument:
      Version: '2012-10-17'
      Statement:
        - Sid: AllowRetrieval
          Effect: Allow
          Action:
            - bedrock:Retrieve
            - bedrock:RetrieveAndGenerate
          Resource:
            - !Sub "arn:aws:bedrock:${AWS::Region}:${AWS::AccountId}:knowledge-base/${KnowledgeBaseId}"

# 3. SCP — org-wide model restrictions
# Apply at OU level to restrict all accounts
BedrockModelRestrictionSCP:
  Type: AWS::Organizations::Policy
  Properties:
    Type: SERVICE_CONTROL_POLICY
    Content:
      Version: '2012-10-17'
      Statement:
        - Sid: DenyUnapprovedBedrockModels
          Effect: Deny
          Action:
            - bedrock:InvokeModel
            - bedrock:InvokeModelWithResponseStream
          Resource: "*"
          Condition:
            StringNotLike:
              bedrock:ModelId:
                - "anthropic.claude-*"
                - "amazon.titan-*"
```
