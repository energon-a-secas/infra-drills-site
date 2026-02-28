# Solution for Resource Limits OOMKilled

## The Issue

The nginx pod is being terminated by the kernel's OOM (Out of Memory) killer because its memory limit is set to `10Mi`, which is far too low for an nginx process. When the container's memory usage exceeds the limit defined in `resources.limits.memory`, Kubernetes terminates the container with reason `OOMKilled`. The kubelet then restarts the container according to the pod's restart policy, resulting in a `CrashLoopBackOff` cycle.

## Solution

Increase the memory limit to a value that accommodates nginx's baseline memory consumption. A limit of `128Mi` is appropriate for a standard nginx container.

### Step 1: Identify the problem

```bash
kubectl get pods -l app=nginx-app
```

You will see the pod in `CrashLoopBackOff` status. Get more details:

```bash
kubectl describe pod -l app=nginx-app
```

In the output, look for:

```
Last State:     Terminated
  Reason:       OOMKilled
  Exit Code:    137
```

### Step 2: Fix the deployment

Edit the deployment to increase the memory limits:

```bash
kubectl edit deployment nginx-app
```

Change the resources section from:

```yaml
resources:
  requests:
    memory: "5Mi"
    cpu: "50m"
  limits:
    memory: "10Mi"
    cpu: "100m"
```

To:

```yaml
resources:
  requests:
    memory: "64Mi"
    cpu: "50m"
  limits:
    memory: "128Mi"
    cpu: "100m"
```

Alternatively, apply the fix with `kubectl patch`:

```bash
kubectl patch deployment nginx-app --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/memory", "value": "64Mi"},
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/memory", "value": "128Mi"}
]'
```

## Understanding

### OOMKilled

When a container exceeds its memory limit, the Linux kernel's OOM killer terminates the process. Kubernetes reports this as `OOMKilled` (exit code 137, which is 128 + signal 9 SIGKILL). The container is then restarted, and if it keeps getting killed, Kubernetes enters `CrashLoopBackOff` with increasing back-off delays.

### Resource Requests vs Limits

- **Requests** (`resources.requests`): The amount of resources guaranteed to the container. The Kubernetes scheduler uses requests to decide which node to place the pod on. A container is guaranteed to have at least this amount available.
- **Limits** (`resources.limits`): The maximum amount of resources a container can consume. For memory, exceeding the limit results in OOMKilled. For CPU, the container is throttled but not terminated.

### Choosing Appropriate Values

- Always profile your application to understand its baseline resource consumption before setting limits.
- Set requests close to the application's steady-state usage.
- Set limits to accommodate reasonable spikes above steady-state usage.
- Nginx typically requires at least 50-100Mi of memory at baseline.

## Testing

After applying the fix, verify the pod is running:

```bash
kubectl get pods -l app=nginx-app
```

Expected output:

```
NAME                         READY   STATUS    RESTARTS   AGE
nginx-app-xxxxxxxxx-xxxxx    1/1     Running   0          30s
```

Verify the updated resource limits:

```bash
kubectl describe pod -l app=nginx-app | grep -A 6 "Limits:"
```

## Common Mistakes

- **Setting limits too close to requests**: This leaves no headroom for memory spikes, causing intermittent OOMKills under load.
- **Only increasing requests without increasing limits**: If the limit stays at 10Mi, the pod will still be OOMKilled regardless of the request value.
- **Confusing CPU and memory behavior**: CPU limits cause throttling (the container slows down), while memory limits cause termination (the container is killed). They require different strategies.
- **Not checking events**: Running only `kubectl get pods` shows `CrashLoopBackOff` but not the root cause. Always use `kubectl describe pod` to see the `OOMKilled` reason.

## Additional Resources

- [Kubernetes Resource Management for Pods and Containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [Kubernetes Assign Memory Resources to Containers](https://kubernetes.io/docs/tasks/configure-pod-container/assign-memory-resource/)
- [Understanding OOMKilled in Kubernetes](https://kubernetes.io/docs/tasks/configure-pod-container/assign-memory-resource/#exceed-a-containers-memory-limit)
