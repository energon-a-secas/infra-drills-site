# Triage 02: App Crash After Rollback

## Root Cause

Two failures caused the crash:

1. **The v2.0.0 deploy used a non-existent image**. This caused the initial CrashLoopBackOff (ImagePullBackOff).
2. **The ConfigMap `payments-config` was deleted** between the deploy and the rollback, possibly by a cleanup script, another team member, or a separate change.

The rollback reverted the image back to v1.0.0 (nginx:1.25), which is correct. But v1.0.0 mounts `payments-config` via `envFrom.configMapRef`. Since the ConfigMap no longer exists, the pod cannot start, Kubernetes blocks container creation when a required ConfigMap is missing.

The team assumed the rollback restored everything to the previous state. It restored the Deployment spec, but not the cluster resources the Deployment depends on.

## Diagnostic Path

### 1. Check pod status

```bash
kubectl get pods -l app=payments-api
```

Pods show `CreateContainerConfigError` or `CrashLoopBackOff`.

### 2. Describe the pod

```bash
kubectl describe pod -l app=payments-api
```

Events section shows:
```
Warning  Failed  configmap "payments-config" not found
```

This is the key clue: the pod depends on a ConfigMap that does not exist.

### 3. Check the deployment spec

```bash
kubectl get deployment payments-api -o yaml | grep -A 5 envFrom
```

The spec references `configMapRef: name: payments-config`.

### 4. Verify the ConfigMap is missing

```bash
kubectl get configmap payments-config
```

Returns `Error from server (NotFound)`. The ConfigMap was deleted.

### 5. Check rollout history

```bash
kubectl rollout history deployment/payments-api
```

Shows two revisions. The rollback went to revision 1, which is the correct image, but the ConfigMap it depends on is gone.

## Solution

Recreate the missing ConfigMap:

```bash
kubectl create configmap payments-config \
    --from-literal=DB_HOST=postgres.default.svc \
    --from-literal=DB_PORT=5432
```

The pod should start within seconds. Verify:

```bash
kubectl get pods -l app=payments-api
```

Should show `Running` with `1/1` ready.

## What to Suspect When Rollbacks Fail

A rollback only reverts the Deployment spec (image, env, volumes, etc.). It does not restore:

- **ConfigMaps or Secrets** that were deleted or modified
- **PersistentVolumeClaims** that were removed
- **Services, Ingresses, or NetworkPolicies** that changed
- **Database schemas** that were migrated forward
- **External state** (feature flags, DNS records, certificates)

When a rollback "succeeds" but pods still fail, check what the Deployment depends on outside its own spec.

## Triage Lessons

- **Rollbacks revert the Deployment spec, not the cluster state.** Deleted ConfigMaps, Secrets, and PVCs stay deleted.
- **Read the pod events.** `kubectl describe pod` almost always tells you exactly what is wrong. In this case, "configmap not found" points directly to the root cause.
- **Ask "what else changed?"** The ticket focuses on the deploy and rollback, but the real problem was a separate action (ConfigMap deletion) that happened in between.

## Common Mistakes

1. **Assuming the rollback is broken**: The rollback restored the Deployment spec correctly. The problem is in cluster resources the Deployment depends on, not in the spec itself.
2. **Reapplying the entire Deployment YAML**, If you reapply the v1.0.0 manifest, you still have the same problem because the ConfigMap is missing.
3. **Deleting and recreating the pod**: The new pod will fail for the same reason. The ConfigMap must exist first.
4. **Not reading the pod events**: The error message explicitly says which ConfigMap is missing. Skipping `kubectl describe` means guessing when the answer is right there.
