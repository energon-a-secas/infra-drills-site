## Ticket

**From:** Backend Developer
**Priority:** High
**Subject:** Same deployment works in staging but CrashLoopBackOff in production

> We promoted our `checkout` service from staging to production this
> morning. It has been running fine in staging for two weeks. In production
> the pod never comes up — it just cycles through CrashLoopBackOff.
>
> We deployed the exact same image and the exact same YAML. Nothing is
> different between the two environments. I even copied the manifests from
> the staging folder.
>
> Can someone check if the production cluster is broken?
>
> Namespaces: `staging` (working) and `production` (broken)
> Service: checkout

### What You Know

- The `checkout` pod is Running in `staging` and CrashLoopBackOff in `production`.
- The developer insists the image and YAML are identical.
- "Nothing is different" is the claim to test, not the fact to trust.
- Both namespaces exist and the image pulls fine (it starts, then exits).

### Your Task

1. Confirm the pod is healthy in `staging` and crashing in `production`.
2. Diff the two environments to find what actually differs.
3. Fix production so the pod reaches a Ready state.

## Lab Setup

```bash
cd triage-10-crashloop-one-environment
bash lab-initialization.sh
```

## Validation

```bash
# The production pod should reach Running and stay there (no restarts climbing):
kubectl get pods -n production -l app=checkout
kubectl rollout status deployment/checkout -n production --timeout=60s
```

The production `checkout` pod should be `Running` `1/1` and the rollout should report success.

## [Solution](../solutions/triage-10-crashloop-one-environment.md)
