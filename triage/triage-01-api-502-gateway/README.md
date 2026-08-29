## Ticket

**From:** Backend Team Lead
**Priority:** High
**Subject:** API returning 502 since this morning

> Our /status endpoint started returning 502 Bad Gateway around 9 AM.
> We haven't deployed anything new. The Lambda function was working fine
> yesterday. Customers are affected: please investigate ASAP.
>
> API URL: https://api.example.com/status
> Lambda: status-checker
>
> We checked CloudWatch and the function doesn't seem to be invoked at all.

### What You Know

- The API is served through API Gateway backed by a Lambda function.
- The team says nothing changed. (They always say that.)
- The Lambda function "status-checker" exists in LocalStack.
- The function worked correctly before.

### Your Task

1. Find out why the API returns 502.
2. Identify what changed.
3. Fix the root cause.

## Lab Setup

```bash
cd triage-01-api-502-gateway
bash lab-initialization.sh
```

## Validation

```bash
awslocal lambda invoke --function-name status-checker --payload '{}' /tmp/response.json && cat /tmp/response.json
```

The function should return a 200 response with a status message.

## [Solution](../solutions/triage-01-api-502-gateway.md)
