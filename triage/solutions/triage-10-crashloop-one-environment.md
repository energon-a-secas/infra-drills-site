# Triage 10: Same Deployment, Crashes in One Environment

## Root Cause

The Deployments in `staging` and `production` are genuinely identical. The difference is in the `checkout-config` ConfigMap that each namespace owns:

- `staging` defines the key `DATABASE_URL` (correct).
- `production` defines the key `DATABASE_URI` (a typo).

The container reads its environment with `envFrom.configMapRef`, then hard-exits when `DATABASE_URL` is empty. In production the correct key never gets injected, `DATABASE_URL` is empty, and the container exits 1 on every start, producing CrashLoopBackOff.

The developer's claim ("same image, same YAML") is true and also a red herring. The workload manifests match; the *environment-scoped configuration* does not. This is why comparison, not code review, is the fastest path to the answer.

## Diagnostic Path

### 1. Confirm the asymmetry

```bash
kubectl get pods -n staging -l app=checkout
kubectl get pods -n production -l app=checkout
```

`staging` is `Running`; `production` is `CrashLoopBackOff` with a climbing restart count. One environment works, one doesn't — a strong signal to *diff the environments* rather than debug the app.

### 2. Read why the container is exiting

```bash
kubectl logs -n production -l app=checkout --previous
```

```
FATAL: DATABASE_URL is empty — cannot connect to database
```

The app tells you exactly what it needs. Now the question is *why* `DATABASE_URL` is empty in production only.

### 3. Compare the two environments directly

Diff the Deployments first to eliminate them:

```bash
diff \
  <(kubectl get deployment checkout -n staging  -o yaml | grep -v -E 'namespace:|resourceVersion:|uid:|creationTimestamp:|generation:') \
  <(kubectl get deployment checkout -n production -o yaml | grep -v -E 'namespace:|resourceVersion:|uid:|creationTimestamp:|generation:')
```

No meaningful difference. The workloads are the same, exactly as reported. Now compare the thing the Deployment depends on:

```bash
diff \
  <(kubectl get configmap checkout-config -n staging    -o jsonpath='{.data}') \
  <(kubectl get configmap checkout-config -n production -o jsonpath='{.data}')
```

Staging has `DATABASE_URL`; production has `DATABASE_URI`. That single character is the incident.

## Solution

Fix the production ConfigMap key to match what the container reads, then restart the rollout:

```bash
kubectl create configmap checkout-config -n production \
  --from-literal=DATABASE_URL="postgres://checkout:secret@db.production.svc:5432/checkout" \
  --from-literal=LOG_LEVEL="info" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl rollout restart deployment/checkout -n production
kubectl rollout status  deployment/checkout -n production --timeout=60s
```

The pod injects a non-empty `DATABASE_URL`, starts cleanly, and stays Running.

## Triage Lessons

- **"Nothing is different" is a hypothesis, not evidence.** When the same artifact behaves differently in two places, something in the environment differs. Your job is to find it, not to accept the claim.
- **When one environment works and another doesn't, diff them.** The working environment is a free known-good reference. The delta between good and broken is a short, high-value suspect list.
- **Diff outward from the workload.** Deployment first (rule it out), then its ConfigMaps, Secrets, ServiceAccounts, and namespace-scoped policies. Config drift between environments hides in exactly these places.
- **Let the logs narrow the search before you diff.** The `--previous` logs named `DATABASE_URL` specifically, so you compared the right key instead of eyeballing entire manifests.

## Common Mistakes

1. **Debugging the application code.** The image is identical and healthy in staging. The code is not the bug; the environment config is.
2. **Blaming the production cluster.** The cluster schedules and runs the pod fine. It faithfully starts a container that then exits on its own.
3. **Comparing manifests by eye instead of with `diff`.** The Deployments match, so a visual scan of production alone finds nothing. The signal only appears when staging and production are placed side by side.
4. **Deleting and recreating the pod.** It reschedules into the same broken ConfigMap and crash-loops again. The fix is in the configuration, not the pod lifecycle.
