### Bedrock Agent Action Group Lambda Pattern

Lambda functions invoked by Bedrock Agents as action groups with confused deputy prevention and least-privilege execution roles.

**When to use**: ['Bedrock Agent action groups', 'Lambda functions called by AI agents', 'Serverless AI tool execution']

```yaml
# template.yaml — Bedrock Agent Action Group Lambda
Resources:
  AgentActionFunction:
    Type: AWS::Serverless::Function
    Properties:
      Handler: src/handlers/agent-action.handler
      Runtime: nodejs20.x
      Timeout: 30
      MemorySize: 256
      Environment:
        Variables:
          TABLE_NAME: !Ref DataTable
      Policies:
        # Least privilege — only the specific table this action needs
        - DynamoDBReadPolicy:
            TableName: !Ref DataTable

  # Confused deputy prevention — restrict which agents can invoke this Lambda
  AgentActionFunctionPermission:
    Type: AWS::Lambda::Permission
    Properties:
      FunctionName: !Ref AgentActionFunction
      Action: lambda:InvokeFunction
      Principal: bedrock.amazonaws.com
      SourceAccount: !Ref AWS::AccountId
      SourceArn: !Sub "arn:aws:bedrock:${AWS::Region}:${AWS::AccountId}:agent/*"

  DataTable:
    Type: AWS::DynamoDB::Table
    Properties:
      AttributeDefinitions:
        - AttributeName: id
          AttributeType: S
      KeySchema:
        - AttributeName: id
          KeyType: HASH
      BillingMode: PAY_PER_REQUEST
```

```javascript
// src/handlers/agent-action.js
// Bedrock Agent action group handler
// Agents send a structured event with apiPath, httpMethod, and parameters

exports.handler = async (event, context) => {
  const { apiPath, httpMethod, parameters, requestBody } = event;
  const actionGroup = event.actionGroup;
  const agent = event.agent;

  console.log('Agent action:', JSON.stringify({
    actionGroup,
    apiPath,
    httpMethod,
    agentId: agent?.id,
    requestId: context.awsRequestId
  }));

  try {
    let result;

    // Route based on the OpenAPI-defined action
    if (apiPath === '/forecast' && httpMethod === 'GET') {
      const spotId = parameters?.find(p => p.name === 'spotId')?.value;
      result = await getForecast(spotId);
    } else if (apiPath === '/spots' && httpMethod === 'GET') {
      result = await listSpots();
    } else {
      return formatAgentResponse(event, 400, { error: `Unknown action: ${httpMethod} ${apiPath}` });
    }

    return formatAgentResponse(event, 200, result);
  } catch (error) {
    console.error('Action group error:', error);
    return formatAgentResponse(event, 500, { error: 'Internal error processing action' });
  }
};

// Bedrock Agent expects a specific response format
function formatAgentResponse(event, statusCode, body) {
  return {
    messageVersion: '1.0',
    response: {
      actionGroup: event.actionGroup,
      apiPath: event.apiPath,
      httpMethod: event.httpMethod,
      httpStatusCode: statusCode,
      responseBody: {
        'application/json': {
          body: JSON.stringify(body)
        }
      }
    }
  };
}
```
