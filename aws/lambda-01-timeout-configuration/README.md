## Problem

My Lambda function keeps returning a timeout error every time I invoke it. I'm using the following command:

```
awslocal lambda invoke --function-name http-checker --payload '{}' /tmp/response.json && cat /tmp/response.json
```

The response always comes back with a `Task timed out` error. The function is supposed to make a simple HTTP request and return the status code, but it never completes.

### Context
- The Lambda function was deployed via CloudFormation and exists in LocalStack
- The function code makes a single HTTP GET request using Python's `urllib`
- The function works correctly when tested locally outside of Lambda
- No VPC or network restrictions are in place

### Hint
Lambda functions have a configurable execution time limit. Check how long the function is allowed to run versus how long the HTTP request actually takes.

## Validation

Your solution should:
- Successfully invoke the Lambda function without a timeout error
- Return a valid HTTP status code in the response

```bash
awslocal lambda invoke --function-name http-checker --payload '{}' /tmp/response.json && cat /tmp/response.json
```

## [Solution](../solutions/lambda-01-timeout-configuration.md)
