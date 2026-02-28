# Solution for Network Policy Blocks Traffic

## The Issue

A `default-deny-ingress` NetworkPolicy is applied to the namespace with an empty `podSelector` (`{}`), which means it matches ALL pods. This policy declares `Ingress` in its `policyTypes` but has no `ingress` rules, so it effectively blocks all incoming traffic to every pod in the namespace. The frontend pod's requests to the backend service are dropped because the backend pod is not allowed to receive any ingress traffic.

## Solution

Create an additional NetworkPolicy that explicitly allows ingress traffic from frontend pods to backend pods on port 80.

### Step 1: Identify the problem

Check for NetworkPolicies in the namespace:

```bash
kubectl get networkpolicy
```

You will see the `default-deny-ingress` policy:

```
NAME                     POD-SELECTOR   AGE
default-deny-ingress     <none>         2m
```

Inspect the policy:

```bash
kubectl describe networkpolicy default-deny-ingress
```

Notice that it selects all pods (`podSelector: {}`) and has `Ingress` in `policyTypes` with no ingress rules defined. This means all ingress is denied.

### Step 2: Verify the pods are running

```bash
kubectl get pods -l app=backend
kubectl get pods -l app=frontend
```

Both pods should show `Running` status, confirming the issue is not with the pods themselves.

### Step 3: Confirm the connectivity failure

```bash
kubectl exec -it $(kubectl get pod -l app=frontend -o jsonpath='{.items[0].metadata.name}') -- wget -qO- --timeout=5 http://backend
```

This will time out, confirming the network path is blocked.

### Step 4: Create an allow NetworkPolicy

Create a file called `allow-frontend-to-backend.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - protocol: TCP
      port: 80
```

Apply it:

```bash
kubectl apply -f allow-frontend-to-backend.yaml
```

Alternatively, apply it inline:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - protocol: TCP
      port: 80
EOF
```

## Understanding

### NetworkPolicies

NetworkPolicies are Kubernetes resources that control traffic flow at the IP/port level (OSI layer 3/4). By default, Kubernetes allows all traffic between pods. NetworkPolicies let you restrict this by specifying rules for ingress (incoming) and egress (outgoing) traffic.

Key concepts:

- **podSelector**: Determines which pods the policy applies to. An empty selector (`{}`) matches all pods in the namespace.
- **policyTypes**: Specifies whether the policy applies to `Ingress`, `Egress`, or both.
- **ingress/egress rules**: Define allowed traffic sources/destinations. If a policyType is listed but no rules are defined, all traffic of that type is denied.

### Default Deny Pattern

The default-deny pattern uses a NetworkPolicy with an empty podSelector and a policyType but no rules. This blocks all traffic of that type for every pod in the namespace. It is a common security best practice to start with default-deny and then add specific allow rules.

```yaml
# Default deny all ingress
spec:
  podSelector: {}       # Applies to ALL pods
  policyTypes:
  - Ingress             # No ingress rules = deny all ingress
```

### How Allow Rules Work With Default Deny

NetworkPolicies are additive. When a pod is selected by any NetworkPolicy, only traffic explicitly allowed by at least one policy is permitted. Adding the `allow-frontend-to-backend` policy does not override the default-deny; instead, the backend pod is now selected by both policies, and the union of their rules applies. Since the allow policy permits ingress from frontend pods on port 80, that specific traffic is allowed.

### CNI Plugin Requirement

NetworkPolicies require a CNI (Container Network Interface) plugin that supports them. In Minikube, you need to enable the CNI plugin (e.g., Calico) for NetworkPolicies to take effect. Without a compatible CNI, the NetworkPolicy resources are accepted but not enforced.

To enable Calico in Minikube:

```bash
minikube start --cni=calico
```

## Testing

Verify the allow policy was created:

```bash
kubectl get networkpolicy
```

Expected output:

```
NAME                          POD-SELECTOR    AGE
allow-frontend-to-backend     app=backend     10s
default-deny-ingress          <none>          5m
```

Test connectivity from frontend to backend:

```bash
kubectl exec -it $(kubectl get pod -l app=frontend -o jsonpath='{.items[0].metadata.name}') -- wget -qO- --timeout=5 http://backend
```

You should see the nginx default HTML page returned successfully.

## Common Mistakes

- **Putting the wrong podSelector on the allow policy**: The `podSelector` in the allow policy must match the pods you want to allow traffic TO (the backend), not FROM. The `from` section specifies the source pods (frontend).
- **Forgetting to include the port in the allow rule**: Without specifying `ports` in the ingress rule, all ports are allowed from the frontend, which is more permissive than necessary.
- **Deleting the default-deny policy instead of adding an allow rule**: While this fixes the immediate issue, it removes the security posture entirely. The correct approach is to keep default-deny and add targeted allow rules.
- **Mixing up namespace selectors and pod selectors**: When frontend and backend are in the same namespace, only `podSelector` is needed. The `namespaceSelector` is used when allowing traffic from pods in a different namespace.
- **Not having a CNI plugin that supports NetworkPolicies**: In Minikube, you must start with `--cni=calico` (or another NetworkPolicy-capable CNI). The default Minikube CNI does not enforce NetworkPolicies.

## Additional Resources

- [Kubernetes Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Declare Network Policy](https://kubernetes.io/docs/tasks/administer-cluster/declare-network-policy/)
- [NetworkPolicy Recipes](https://github.com/ahmetb/kubernetes-network-policy-recipes)
- [Minikube CNI Configuration](https://minikube.sigs.k8s.io/docs/handbook/network_policy/)
