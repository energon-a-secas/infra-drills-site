# Problem/Request

A frontend pod cannot connect to the backend service. All connection attempts from the frontend to the backend time out. The frontend and backend were communicating normally until a recent change was applied to the namespace.

* Context: A new security policy was deployed to the namespace to enforce a "default deny" posture. After the policy was applied, the frontend pod can no longer reach the backend service on port 80. Both pods are running and healthy individually.
* Hint: Check if any NetworkPolicies exist in the namespace with `kubectl get networkpolicy`. A default-deny policy blocks all ingress traffic unless an explicit allow rule is created.

# Validation

To validate the solution, exec into the frontend pod and curl the backend service:

```
kubectl exec -it $(kubectl get pod -l app=frontend -o jsonpath='{.items[0].metadata.name}') -- wget -qO- --timeout=5 http://backend
```

The command should return the nginx default HTML page without timing out.

Solution: [../solutions/k8s-10-network-policy-blocks-traffic.md](../solutions/k8s-10-network-policy-blocks-traffic.md)
