# Problem/Request

A pod keeps crashing with `CrashLoopBackOff` status shortly after being created. The application never becomes available.

* Context: The deployment was recently updated with resource limits to comply with cluster resource policies. Since the update, the pod has been unable to stay running.
* Hint: Check the pod events with `kubectl describe pod` and look at the "Last State" reason for the container.

# Validation

To validate the solution, verify that the pod is running successfully:

```
kubectl get pods -l app=nginx-app
```

The pod should show a `Running` status with `1/1` containers ready and zero restarts (or no new restarts after the fix).

Solution: [../solutions/k8s-02-resource-limits-oom.md](../solutions/k8s-02-resource-limits-oom.md)
