# Problem/Request

A deployment's rolling update is stuck. Some pods are in `ImagePullBackOff` or `ErrImagePull` status while the old pods are still running. The deployment never completes the rollout.

* Context: A deployment named `web-server` with 3 replicas was updated to use a new image tag, but something went wrong during the update. The application is partially available with old pods still serving traffic, but the new version cannot start.
* Hint: Check the image tag in the deployment spec and verify it exists. Look at the pod events with `kubectl describe pod` for image pull errors.

# Validation

To validate the solution, verify that all pods are running and the deployment is fully rolled out:

```
kubectl rollout status deployment/web-server
kubectl get pods -l app=web-server
```

The rollout should report `successfully rolled out` and all 3 pods should show `Running` status with `1/1` containers ready.

Solution: [../solutions/k8s-11-rolling-update-stuck.md](../solutions/k8s-11-rolling-update-stuck.md)
