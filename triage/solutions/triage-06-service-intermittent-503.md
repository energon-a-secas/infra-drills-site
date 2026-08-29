# Triage 06: Service Intermittent 503

## Root Cause

Two Deployments serve the same Service via the shared label `app: frontend-api`. One pod declares `containerPort: 80` (correct, matches nginx), the other declares `containerPort: 9090` (wrong, nginx still listens on 80).

Both pods are Running and Ready. Without a readiness probe, Kubernetes cannot detect the port mismatch. The Service selects both pods and creates endpoints for both. When traffic hits the good pod, it returns 200. When it hits the bad pod, nothing listens on port 9090 from the Service's perspective.

The roughly 50% failure rate matches round-robin between 2 endpoints.

## Diagnostic Path

### 1. Check the endpoints

```bash
kubectl get endpoints frontend-api
```

Shows 2 IP addresses. Both pods are registered as endpoints.

### 2. Check both pods

```bash
kubectl get pods -l app=frontend-api -o wide
```

Both show Running 1/1. Nothing obvious.

### 3. Describe the pods and compare

```bash
kubectl get pods -l app=frontend-api -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].ports[0].containerPort}{"\n"}{end}'
```

One pod declares `containerPort: 80`, the other declares `containerPort: 9090`. The nginx image always listens on 80 regardless of what containerPort says, but the mismatch between the declared port and the Service targetPort affects endpoint routing.

### 4. Test each pod individually

```bash
# Get pod names
GOOD_POD=$(kubectl get pods -l version=good -o jsonpath='{.items[0].metadata.name}')
BAD_POD=$(kubectl get pods -l version=bad -o jsonpath='{.items[0].metadata.name}')

# Test good pod directly
kubectl port-forward $GOOD_POD 8081:80 &
curl -s http://localhost:8081  # Returns nginx welcome page
kill %1

# Test bad pod directly on port 80 (not 9090)
kubectl port-forward $BAD_POD 8082:80 &
curl -s http://localhost:8082  # Also returns nginx welcome page
kill %1
```

Both pods work on port 80. The issue is that one pod's endpoint is registered with the wrong port.

## Solution

Fix the bad deployment's containerPort to match what nginx actually listens on:

```bash
kubectl patch deployment frontend-api-bad -p '{"spec":{"template":{"spec":{"containers":[{"name":"nginx","ports":[{"containerPort":80}]}]}}}}'
```

Or edit the manifest to set `containerPort: 80` and reapply.

Better long-term fix: use a single Deployment with 2 replicas instead of two separate Deployments with the same label.

## Triage Lessons

- **"Both pods are Running" does not mean both are serving correctly.** Running only means the container process started. Without readiness probes, Kubernetes cannot tell if the pod is actually serving traffic.
- **Check endpoints, not just pods.** `kubectl get endpoints` shows which pod IPs and ports the Service routes to. A wrong port here explains intermittent failures.
- **Intermittent failures that correlate with replica count point to one bad replica.** If it fails ~50% of the time with 2 replicas, one replica is broken. With 3 replicas, it would fail ~33%.

## Common Mistakes

1. **Blaming the Service configuration**: The Service is correct (targetPort: 80). The issue is in one pod's declared containerPort.
2. **Restarting all pods**: Both pods restart into the same configuration. The bug is in the Deployment spec.
3. **Not checking endpoints**: Jumping to network debugging without first verifying that the Service endpoints are correct.
4. **Assuming containerPort is just documentation**, containerPort affects endpoint registration and some CNI routing, even though it is often treated as informational.
