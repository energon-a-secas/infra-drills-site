## Ticket

**From:** Application Developer
**Priority:** High
**Subject:** Payments service can't reach the new provider after migration

> We migrated our payment provider endpoint last night. The new host is
> `api.payments-v2.internal`. Ops updated the SSM parameter with the new
> URL and confirmed the change went through.
>
> But our `charge` function still can't connect. It keeps timing out
> against the OLD host `api.payments-v1.internal`, which we already
> decommissioned. Since the config is definitely updated, this has to be
> a DNS or network problem — the runner is caching the old address, or
> the firewall is blocking the new one.
>
> Can infra check the network path to the new endpoint?
>
> Parameter: /payments/charge/endpoint  (SSM Parameter Store)

### What You Know

- The service reads its endpoint from the SSM parameter `/payments/charge/endpoint`.
- Ops *say* they updated the parameter to the new host.
- The app is still hitting the OLD host, which no longer exists.
- The ticket has already concluded "it's the network" without checking the config.

### Your Task

1. Do not accept "the config is definitely updated." Verify it.
2. Read the value the application actually reads at runtime.
3. Fix the source of the stale endpoint so the app targets the new host.

## Lab Setup

Requires LocalStack running (`cd ../../aws && make run`).

```bash
cd triage-12-config-assumed-updated
bash lab-initialization.sh
```

## Validation

```bash
# The parameter the app reads should return the NEW host:
awslocal ssm get-parameter --name /payments/charge/endpoint \
  --query 'Parameter.Value' --output text
```

The value should be `https://api.payments-v2.internal/charge` (the new host), not the decommissioned `v1` host.

## [Solution](../solutions/triage-12-config-assumed-updated.md)
