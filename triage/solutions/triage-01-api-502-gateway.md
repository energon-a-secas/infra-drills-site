# Triage 01: API 502 Bad Gateway

## Root Cause

The Lambda handler is set to `index.main`, but the function defines `handler`. The function deploys without error, but the runtime fails on every invocation because it cannot find the entry point `main`.

The "nothing changed" claim is false: someone updated the function configuration (likely during a deploy or a manual fix) and introduced a typo in the handler name.

## Diagnostic Path

### 1. Check if the function exists

```bash
awslocal lambda get-function --function-name status-checker
```

The function exists. Nothing obviously wrong here.

### 2. Try invoking the function directly

```bash
awslocal lambda invoke --function-name status-checker --payload '{}' /tmp/response.json && cat /tmp/response.json
```

The response contains an error: `"Handler 'index.main' missing on module 'index'"` or a similar runtime import error. This is the key clue.

### 3. Check the function configuration

```bash
awslocal lambda get-function-configuration --function-name status-checker
```

Look at the `Handler` field. It says `index.main`. Python Lambda handlers follow the format `module.function_name`. The module is `index` (from `index.py`), but the function is `handler`, not `main`.

### 4. Check CloudWatch logs (if available)

```bash
awslocal logs filter-log-events --log-group-name /aws/lambda/status-checker
```

Logs would show the import/handler error on each invocation attempt.

## Solution

Fix the handler name:

```bash
awslocal lambda update-function-configuration \
    --function-name status-checker \
    --handler index.handler
```

Verify:

```bash
awslocal lambda invoke --function-name status-checker --payload '{}' /tmp/response.json && cat /tmp/response.json
```

Should return:

```json
{
    "statusCode": 200,
    "body": "{\"status\": \"healthy\", \"service\": \"status-checker\", \"version\": \"1.2.0\"}"
}
```

## What to Suspect When You See 502

A 502 Bad Gateway from API Gateway + Lambda usually means:

1. **Lambda failed to execute**: handler error, import error, or runtime crash
2. **Lambda timed out**: execution exceeded the configured timeout
3. **Lambda returned an invalid response**, missing statusCode, wrong format for proxy integration
4. **Permission issue**: API Gateway cannot invoke the Lambda function

The first diagnostic step is always: invoke the function directly, bypassing API Gateway. If direct invocation fails, the problem is in the function. If direct invocation works but the API still returns 502, the problem is in the API Gateway integration.

## Triage Lessons

- **"Nothing changed" is almost never true.** Someone deployed, updated a config, or a dependency shifted. Always verify by checking recent changes, deployment history, or CloudTrail events.
- **Start by reproducing the failure.** Before theorizing, invoke the function directly and read the actual error.
- **Check the function configuration, not just the code.** Handler name, runtime version, timeout, memory, environment variables. Any of these can break a working function without touching the code.

## Common Mistakes

1. **Assuming the code is wrong**: The code is fine. The configuration points to the wrong entry point.
2. **Redeploying the same code**: If the handler name is wrong in the deployment config, redeploying just recreates the same problem.
3. **Only checking API Gateway**: The 502 originates from the Lambda failure, not from API Gateway misconfiguration.
4. **Not reading the invocation error**: The error message explicitly says which handler is missing.
