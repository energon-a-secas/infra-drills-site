# Problem/Request

A pod is stuck in `ContainerCreating` status and never transitions to `Running`. The application is completely unavailable.

* Context: A deployment was applied to the cluster, but the ConfigMap it references was never created. The deployment expects configuration to be mounted as a volume.
* Hint: Check the pod events with `kubectl describe pod` and look for warnings mentioning "configmap" not found.

# Validation

To validate the solution, verify that the pod is running successfully:

```
kubectl get pods -l app=web-app
```

The pod should show a `Running` status with `1/1` containers ready.

Solution: [../solutions/k8s-03-configmap-mount-failure.md](../solutions/k8s-03-configmap-mount-failure.md)
