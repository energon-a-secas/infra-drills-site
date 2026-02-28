# Problem/Request

An HPA (Horizontal Pod Autoscaler) is configured to scale a Deployment based on CPU utilization, but `kubectl get hpa` shows `<unknown>/80%` for the CPU target and the replica count stays at 1 even under load.

* Context: An HPA was created targeting the `web-app` Deployment with a CPU target utilization of 80%. A load generator has been running against the service, but the Deployment never scales beyond 1 replica. The pods are running and serving traffic.
* Hint: Check two things: first, whether the HPA can read metrics (`kubectl describe hpa`), and second, whether the Deployment containers have CPU resource requests defined (`kubectl get deployment web-app -o yaml | grep -A5 resources`). The HPA calculates utilization as a percentage of the requested CPU, so without requests it cannot compute the percentage.

# Validation

To validate the solution, check that the HPA shows actual CPU metrics:

```
kubectl get hpa web-app-hpa
```

The TARGETS column should display an actual CPU percentage instead of `<unknown>` (e.g., `45%/80%`).

Generate load and confirm the HPA scales the Deployment:

```
kubectl run load-generator --image=busybox:1.36 --restart=Never -- /bin/sh -c "while true; do wget -q -O- http://web-app; done"
kubectl get hpa web-app-hpa -w
```

After a few minutes, the REPLICAS column should increase beyond 1.

Clean up the load generator when done:

```
kubectl delete pod load-generator
```

Solution: [../solutions/k8s-14-hpa-not-scaling.md](../solutions/k8s-14-hpa-not-scaling.md)
