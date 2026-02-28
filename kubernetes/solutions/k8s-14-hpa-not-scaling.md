# Solution for HPA Not Scaling

## The Issue

There are two problems preventing the HPA from scaling:

1. **Metrics Server is not installed**: The HPA relies on the Kubernetes Metrics API to read CPU and memory usage from pods. Without Metrics Server, the HPA cannot retrieve any metrics and reports `<unknown>` for the current value.

2. **The Deployment has no CPU resource requests**: Even when Metrics Server is available, the HPA calculates CPU utilization as `(actual CPU usage) / (requested CPU)`. If no CPU request is set on the container, the HPA cannot compute a utilization percentage because there is no denominator. It will show `<unknown>` and refuse to scale.

Both problems must be fixed for the HPA to function correctly.

## Solution

Install Metrics Server and add CPU resource requests to the Deployment.

### Step 1: Identify the problem

Check the HPA status:

```bash
kubectl get hpa web-app-hpa
```

You will see:

```
NAME          REFERENCE             TARGETS         MINPODS   MAXPODS   REPLICAS   AGE
web-app-hpa   Deployment/web-app   <unknown>/80%   1         5         1          5m
```

The `<unknown>` indicates the HPA cannot read CPU metrics. Get more details:

```bash
kubectl describe hpa web-app-hpa
```

Look for conditions and events like:

```
Conditions:
  Type            Status  Reason                   Message
  ----            ------  ------                   -------
  AbleToScale     True    SucceededGetScale        the HPA controller was able to get the target's current scale
  ScalingActive   False   FailedGetResourceMetric  the HPA was unable to compute the replica count
```

### Step 2: Install Metrics Server

In Minikube, enable the metrics-server addon:

```bash
minikube addons enable metrics-server
```

Wait for Metrics Server to be ready:

```bash
kubectl -n kube-system rollout status deployment/metrics-server
```

Verify it is working:

```bash
kubectl top nodes
```

If this returns CPU and memory values, Metrics Server is operational.

### Step 3: Add CPU resource requests to the Deployment

Check the current Deployment spec:

```bash
kubectl get deployment web-app -o yaml | grep -A 10 containers
```

Notice there is no `resources` section. Edit the Deployment to add CPU requests:

```bash
kubectl edit deployment web-app
```

Add resource requests under the container spec:

```yaml
spec:
  containers:
  - name: nginx
    image: nginx:1.24
    ports:
    - containerPort: 80
    resources:
      requests:
        cpu: 100m
      limits:
        cpu: 200m
```

Alternatively, patch it:

```bash
kubectl patch deployment web-app --type=json -p='[{"op": "add", "path": "/spec/template/spec/containers/0/resources", "value": {"requests": {"cpu": "100m"}, "limits": {"cpu": "200m"}}}]'
```

This will trigger a rolling update. Wait for the new pods:

```bash
kubectl rollout status deployment/web-app
```

### Step 4: Verify the HPA reads metrics

Wait 1-2 minutes for Metrics Server to collect data from the new pods, then check:

```bash
kubectl get hpa web-app-hpa
```

Expected output:

```
NAME          REFERENCE             TARGETS   MINPODS   MAXPODS   REPLICAS   AGE
web-app-hpa   Deployment/web-app   2%/80%    1         5         1          10m
```

The `<unknown>` is replaced with an actual CPU percentage.

## Understanding

### How the HPA Works

The Horizontal Pod Autoscaler is a control loop that runs every 15 seconds (by default). On each iteration it:

1. **Queries the Metrics API** to get the current CPU (or custom metric) usage for all pods managed by the target Deployment.
2. **Computes the utilization ratio**: `utilization = (current metric value) / (requested metric value)`.
3. **Calculates the desired replica count**: `desiredReplicas = ceil(currentReplicas * (currentUtilization / targetUtilization))`.
4. **Scales the Deployment** up or down if the desired count differs from the current count, subject to stabilization windows.

### Why Resource Requests Are Mandatory

The HPA uses utilization-based scaling, not absolute values. Utilization is defined as:

```
CPU utilization % = (actual CPU used by pod) / (CPU requested by pod) * 100
```

If a pod has no CPU request, the denominator is undefined. The HPA cannot divide by zero, so it reports `<unknown>` and takes no scaling action. This is not a bug; it is an intentional design choice because without requests there is no baseline to measure against.

### Metrics Server

Metrics Server is a cluster-wide aggregator of resource usage data. It collects CPU and memory metrics from the kubelet on each node and exposes them via the Kubernetes Metrics API (`metrics.k8s.io`). It is a prerequisite for:

- `kubectl top nodes` and `kubectl top pods`
- HPA CPU/memory-based autoscaling
- VPA (Vertical Pod Autoscaler) recommendations

Metrics Server is **not** installed by default in most Kubernetes distributions. In managed services (EKS, GKE, AKS), it is usually pre-installed. In Minikube, it must be explicitly enabled.

### Stabilization and Cooldown

Even after metrics are available, the HPA does not scale instantly:

- **Scale-up stabilization window**: Default 0 seconds (scales up immediately when needed).
- **Scale-down stabilization window**: Default 5 minutes. The HPA waits 5 minutes after the last scale event before scaling down, to avoid thrashing.
- **Metric collection delay**: Metrics Server collects data every 15 seconds, and the HPA sync period is also 15 seconds, so there can be up to 30 seconds of latency before a scale decision reflects the current load.

## Testing

Generate load against the service:

```bash
kubectl run load-generator --image=busybox:1.36 --restart=Never -- /bin/sh -c "while true; do wget -q -O- http://web-app; done"
```

Watch the HPA in another terminal:

```bash
kubectl get hpa web-app-hpa -w
```

After 1-3 minutes, you should see the replica count increase:

```
NAME          REFERENCE             TARGETS    MINPODS   MAXPODS   REPLICAS   AGE
web-app-hpa   Deployment/web-app   2%/80%     1         5         1          12m
web-app-hpa   Deployment/web-app   95%/80%    1         5         1          13m
web-app-hpa   Deployment/web-app   95%/80%    1         5         2          13m
web-app-hpa   Deployment/web-app   48%/80%    1         5         2          14m
```

Stop the load generator and wait for scale-down (approximately 5 minutes):

```bash
kubectl delete pod load-generator
kubectl get hpa web-app-hpa -w
```

Verify the Deployment scaled back down:

```bash
kubectl get deployment web-app
```

## Common Mistakes

- **Confusing resource limits with requests for HPA**: The HPA uses **requests**, not limits, to calculate utilization. Setting only `limits` without `requests` will not fix the issue. When only `limits` is set and `requests` is omitted, Kubernetes defaults the request to equal the limit, which works but may not be the desired behavior.
- **Expecting instant scaling**: The HPA has a 15-second sync period and a 5-minute scale-down stabilization window. It takes time for the HPA to observe the metric change and act on it. Under-load scaling up typically takes 30-60 seconds.
- **Forgetting Metrics Server**: This is the most common HPA setup issue. Without Metrics Server, `kubectl top pods` returns an error and the HPA cannot read any metrics. Always verify Metrics Server is running before debugging the HPA itself.
- **Setting CPU requests too high**: If CPU requests are set unrealistically high (e.g., `1000m` when the pod normally uses `50m`), the utilization percentage will always be very low, and the HPA will never trigger a scale-up even under heavy load.
- **Setting CPU requests too low**: Conversely, very low requests (e.g., `1m`) will cause the utilization to spike to thousands of percent with minimal load, triggering aggressive and unnecessary scaling.
- **Not checking HPA events**: `kubectl describe hpa` shows detailed conditions and events that explain exactly why the HPA is not scaling. Always check this before making changes.

## Additional Resources

- [Horizontal Pod Autoscaling](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- [HPA Walkthrough](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/)
- [Metrics Server](https://github.com/kubernetes-sigs/metrics-server)
- [Resource Management for Pods and Containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [Minikube Addons](https://minikube.sigs.k8s.io/docs/commands/addons/)
