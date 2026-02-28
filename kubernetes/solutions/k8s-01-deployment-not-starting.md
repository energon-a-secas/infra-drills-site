# Deployment Not Starting Solution

## The Issue

The deployment `faulty-deployment` uses an `nginx` container that listens on port **80**, but both the liveness probe and readiness probe are configured to send HTTP health checks to port **8080**. Since nothing is listening on port 8080 inside the container, every probe fails immediately with a "connection refused" error. Kubernetes interprets repeated liveness probe failures as the container being unhealthy and kills it, while readiness probe failures prevent the pod from receiving traffic. The result is a pod stuck in a `CrashLoopBackOff` cycle -- it starts, fails health checks, gets killed, restarts, and repeats.

## Solution

Change both probes to target port **80**, which is the port nginx actually listens on:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: faulty-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: faulty-app
  template:
    metadata:
      labels:
        app: faulty-app
    spec:
      containers:
      - name: example-app
        image: nginx
        ports:
        - containerPort: 80
        readinessProbe:
          httpGet:
            path: /
            port: 80          # Was 8080 -- must match containerPort
          initialDelaySeconds: 15
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /
            port: 80          # Was 8080 -- must match containerPort
          initialDelaySeconds: 15
          periodSeconds: 10
```

Apply the corrected manifest:

```bash
kubectl apply -f template.yaml
```

## Diagnosis Walkthrough

When you encounter a deployment that is not starting, here is the step-by-step diagnosis process:

### 1. Check Deployment Status

```bash
kubectl get deployments
```

Look for `READY 0/1` or `AVAILABLE 0`, which indicates pods are not becoming ready.

### 2. Check Pod Status

```bash
kubectl get pods -l app=faulty-app
```

You will likely see one of these statuses:
- `CrashLoopBackOff` -- the container keeps restarting after probe failures
- `Running` but `0/1 READY` -- readiness probe is failing so the pod never becomes ready

### 3. Describe the Pod for Events

```bash
kubectl describe pod -l app=faulty-app
```

In the `Events` section at the bottom, look for lines like:

```
Warning  Unhealthy  Liveness probe failed: Get "http://10.244.0.5:8080/": dial tcp 10.244.0.5:8080: connect: connection refused
Warning  Unhealthy  Readiness probe failed: Get "http://10.244.0.5:8080/": dial tcp 10.244.0.5:8080: connect: connection refused
```

The key clue is `connection refused` on port `8080`. This tells you nothing is listening on that port inside the container.

### 4. Check Container Logs

```bash
kubectl logs -l app=faulty-app --previous
```

The `--previous` flag shows logs from the last terminated container (useful when the container keeps restarting). For nginx, the logs will show it started successfully on port 80, confirming the container itself is healthy -- only the probe configuration is wrong.

### 5. Verify What Port the Container Listens On

If you are unsure which port the application uses, you can exec into a running container:

```bash
kubectl exec -it <pod-name> -- ss -tlnp
```

Or for containers without `ss`:

```bash
kubectl exec -it <pod-name> -- cat /etc/nginx/conf.d/default.conf
```

This will show nginx is configured to `listen 80`.

## Understanding Liveness and Readiness Probes

### Liveness Probe

The liveness probe tells Kubernetes whether the container is **alive**. If the liveness probe fails for the configured number of consecutive times (`failureThreshold`, default 3), Kubernetes kills the container and restarts it according to the pod's `restartPolicy`.

Use cases for liveness probes:
- Detecting deadlocked applications that are running but not responding
- Catching unrecoverable states where a restart would fix the problem

### Readiness Probe

The readiness probe tells Kubernetes whether the container is **ready to serve traffic**. If the readiness probe fails, the pod is removed from the Service endpoints -- it stops receiving traffic but is not killed.

Use cases for readiness probes:
- Waiting for the application to finish loading data or caches
- Temporarily removing a pod from rotation during heavy load or maintenance

### Startup Probe

Kubernetes also offers a **startup probe** (not used in this drill). It runs only during container startup and disables liveness/readiness checks until it succeeds. This is useful for slow-starting applications where you need a long startup window but want aggressive liveness checks after startup.

### Probe Configuration Fields

| Field | Default | Description |
|---|---|---|
| `initialDelaySeconds` | 0 | Seconds to wait before the first probe |
| `periodSeconds` | 10 | How often to run the probe |
| `timeoutSeconds` | 1 | Seconds before the probe times out |
| `successThreshold` | 1 | Consecutive successes to be considered healthy |
| `failureThreshold` | 3 | Consecutive failures before taking action |

## Testing

1. Apply the broken template to observe the failure:

```bash
kubectl apply -f template.yaml
kubectl get pods -l app=faulty-app -w
```

Watch for the pod entering `CrashLoopBackOff` or showing `0/1 READY`.

2. Confirm the probe failure:

```bash
kubectl describe pod -l app=faulty-app | grep -A 5 "Liveness\|Readiness"
```

3. Fix the template by changing both probe ports from `8080` to `80`, then reapply:

```bash
kubectl apply -f template.yaml
```

4. Watch the pod become ready:

```bash
kubectl get pods -l app=faulty-app -w
```

You should see the pod transition to `1/1 Running`.

5. Verify the application is serving traffic:

```bash
kubectl port-forward deployment/faulty-deployment 8080:80
curl http://localhost:8080
```

You should receive the default nginx welcome page HTML.

6. (Optional) Create a Service and validate end-to-end:

```bash
kubectl expose deployment faulty-deployment --port=80 --target-port=80 --type=NodePort
minikube service faulty-deployment --url
```

## Common Mistakes

1. **Probe port does not match containerPort** -- This is the exact bug in this drill. The probe must target the port where the application is actually listening, not an arbitrary port
2. **Confusing Service port with container port in probes** -- Probes run inside the pod network, directly against the container. They have nothing to do with the Service port or NodePort. Always use the `containerPort` value
3. **Setting `initialDelaySeconds` too low** -- If the application takes time to start (e.g., a Java app with Spring Boot), the probe may fail during startup before the app is ready. Increase `initialDelaySeconds` or use a startup probe instead
4. **Using the wrong probe path** -- The health check endpoint must return an HTTP 2xx or 3xx status code. If your app serves `/healthz` but the probe is configured for `/health`, the probe will get a 404 and fail
5. **Only fixing the liveness probe but not the readiness probe** -- Both probes in this template are misconfigured. Fixing only one will still result in problems: fixing liveness alone means the pod will not enter the Ready state and will not receive traffic
6. **Not checking the application image documentation** -- Official images like `nginx`, `httpd`, and `node` have well-documented default ports. Always check the image documentation before writing probes

## Additional Resources

- [Configure Liveness, Readiness and Startup Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
- [Pod Lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)
- [Debugging Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/)
- [Container Probes Reference](https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/pod-v1/#Probe)
- [Kubernetes Health Checks Best Practices](https://cloud.google.com/blog/products/containers-kubernetes/kubernetes-best-practices-setting-up-health-checks-with-readiness-and-liveness-probes)
