# Problem/Request

A Service exists but traffic never reaches the pods. Attempting to curl the Service results in "connection refused" even though the Deployment is running with healthy pods.

* Context: A Deployment called `my-app` is running with all pods in `Running` status. A Service called `my-service` was created to expose the Deployment on port 80, but requests to the Service never reach any pod.
* Hint: Check if the Service has discovered any endpoints with `kubectl get endpoints my-service`. If the ENDPOINTS column is empty, the Service has no backends to route traffic to.

# Validation

To validate the solution, verify that the Service has discovered pod endpoints:

```
kubectl get endpoints my-service
```

The ENDPOINTS column should show one or more pod IP addresses (e.g., `10.244.0.5:80`).

Then confirm traffic reaches the pods by port-forwarding through the Service:

```
kubectl port-forward svc/my-service 8080:80 &
curl localhost:8080
```

You should see the nginx default welcome page.

Solution: [../solutions/k8s-04-service-selector-mismatch.md](../solutions/k8s-04-service-selector-mismatch.md)
