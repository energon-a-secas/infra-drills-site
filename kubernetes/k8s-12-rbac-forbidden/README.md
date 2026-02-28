# Problem/Request

An application pod gets "403 Forbidden" when trying to list pods via the Kubernetes API. The pod's ServiceAccount was created, but API requests fail with a permissions error.

* Context: The pod runs a sidecar script that queries the Kubernetes API at `/api/v1/namespaces/default/pods` using the ServiceAccount token mounted inside the pod. A ServiceAccount named `app-service-account` was created and assigned to the pod, but no Role or RoleBinding was ever created for it. The pod itself starts fine, but every API call returns `403 Forbidden`.
* Hint: Check if any Roles or RoleBindings reference the ServiceAccount with `kubectl get roles` and `kubectl get rolebindings`. A ServiceAccount without any RBAC bindings has no permissions beyond the default.

# Validation

To validate the solution, exec into the pod and query the Kubernetes API:

```
kubectl exec -it $(kubectl get pod -l app=api-reader -o jsonpath='{.items[0].metadata.name}') -- sh -c 'TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token) && wget -qO- --header "Authorization: Bearer $TOKEN" --no-check-certificate https://kubernetes.default.svc/api/v1/namespaces/default/pods 2>&1 | head -20'
```

The command should return a JSON response listing pods in the default namespace (not a `403 Forbidden` error).

Solution: [../solutions/k8s-12-rbac-forbidden.md](../solutions/k8s-12-rbac-forbidden.md)
