## Ticket

**From:** QA Engineer
**Priority:** Medium
**Subject:** Service returns 503 randomly, works sometimes, fails sometimes

> Our frontend-api service is flaky. About half the requests return 200
> and the other half return 503 Service Unavailable. Refreshing the page
> sometimes works, sometimes doesn't.
>
> We have 2 replicas running. Both pods show "Running" in kubectl.
> This started after we scaled from 1 to 2 replicas yesterday.
>
> Namespace: default
> Service: frontend-api

### What You Know

- The service has 2 replicas.
- Scaling from 1 to 2 replicas triggered the issue.
- Both pods appear to be Running.
- Approximately 50% of requests fail: consistent with round-robin load balancing across 2 pods.

### Your Task

1. Determine which pod is causing the 503 errors.
2. Find why one replica is unhealthy while still showing "Running".
3. Fix the issue.

## Lab Setup

```bash
cd triage-06-service-intermittent-503
bash lab-initialization.sh
```

## Validation

```bash
# Port-forward and test multiple times — all should return 200:
kubectl port-forward svc/frontend-api 8080:80 &
for i in $(seq 1 6); do curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080; done
kill %1 2>/dev/null
```

All 6 requests should return 200.

## [Solution](../solutions/triage-06-service-intermittent-503.md)
