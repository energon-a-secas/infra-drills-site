## Ticket

**From:** Platform Engineer
**Priority:** High
**Subject:** Lambda works when I test it but times out in production

> I wrote a Lambda function that calls the GitHub API to check repo stats.
> When I test it with `awslocal lambda invoke`, it returns data perfectly.
> But in production (where it's in a VPC), it always times out after 30s.
>
> I've increased the timeout to 60s. Same thing. The function code is
> identical in both environments.
>
> Function: github-checker
> Production VPC: Has a private subnet for Lambda

### What You Know

- The function makes an outbound HTTPS call to api.github.com.
- It works outside a VPC (direct invoke in LocalStack).
- It times out when placed inside a VPC with only a private subnet.
- The timeout was already increased: it's not a timeout config issue.

### Your Task

1. Understand why a VPC Lambda cannot reach the internet.
2. Identify what network component is missing.
3. Explain the fix (conceptual: full NAT Gateway setup is in the related drill).

## Lab Setup

```bash
cd triage-05-lambda-works-locally-not-prod
bash lab-initialization.sh
```

## Validation

```bash
# Direct invoke should work (simulating non-VPC):
awslocal lambda invoke --function-name github-checker --payload '{}' /tmp/response.json && cat /tmp/response.json
```

The function should return a 200 with GitHub API data.

## [Solution](../solutions/triage-05-lambda-works-locally-not-prod.md)
