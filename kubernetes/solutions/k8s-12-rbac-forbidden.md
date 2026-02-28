# Solution for RBAC Forbidden

## The Issue

The ServiceAccount `app-service-account` is assigned to the pod, but no Role or RoleBinding exists to grant it any permissions. In Kubernetes, ServiceAccounts have no privileges by default (beyond what is granted to the `system:authenticated` group, which does not include listing pods). When the pod uses its mounted ServiceAccount token to call the API server at `/api/v1/namespaces/default/pods`, the API server checks the RBAC rules, finds no matching Role or RoleBinding for the ServiceAccount, and returns `403 Forbidden`.

## Solution

Create a Role that grants permission to list and get pods, and a RoleBinding that binds that Role to the `app-service-account` ServiceAccount.

### Step 1: Identify the problem

Check if any Roles exist in the namespace:

```bash
kubectl get roles
```

This should return `No resources found` or no roles relevant to the ServiceAccount.

Check if any RoleBindings exist:

```bash
kubectl get rolebindings
```

This should also return nothing relevant. Confirm the ServiceAccount exists:

```bash
kubectl get serviceaccount app-service-account
```

Check the pod logs to see the 403 error:

```bash
kubectl logs $(kubectl get pod -l app=api-reader -o jsonpath='{.items[0].metadata.name}')
```

You will see output containing `"code": 403` and `"reason": "Forbidden"`.

### Step 2: Verify the pod is running and uses the ServiceAccount

```bash
kubectl get pods -l app=api-reader
```

The pod should show `Running` status. Verify the ServiceAccount assignment:

```bash
kubectl get pod $(kubectl get pod -l app=api-reader -o jsonpath='{.items[0].metadata.name}') -o jsonpath='{.spec.serviceAccountName}'
```

This should return `app-service-account`.

### Step 3: Create a Role with pod read permissions

Create a file called `pod-reader-role.yaml`:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list"]
```

Apply it:

```bash
kubectl apply -f pod-reader-role.yaml
```

### Step 4: Create a RoleBinding to bind the Role to the ServiceAccount

Create a file called `pod-reader-binding.yaml`:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: app-pod-reader-binding
subjects:
- kind: ServiceAccount
  name: app-service-account
  namespace: default
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

Apply it:

```bash
kubectl apply -f pod-reader-binding.yaml
```

Alternatively, apply both inline:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: app-pod-reader-binding
subjects:
- kind: ServiceAccount
  name: app-service-account
  namespace: default
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
EOF
```

### Step 5: Verify the fix

Wait for the next loop iteration (up to 30 seconds) or exec into the pod to test immediately:

```bash
kubectl exec -it $(kubectl get pod -l app=api-reader -o jsonpath='{.items[0].metadata.name}') -- sh -c 'TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token) && wget -qO- --header "Authorization: Bearer $TOKEN" --no-check-certificate https://kubernetes.default.svc/api/v1/namespaces/default/pods 2>&1 | head -20'
```

The response should now return JSON with a list of pods instead of a 403 error.

## Understanding

### RBAC (Role-Based Access Control)

RBAC in Kubernetes controls who can perform what actions on which resources. The RBAC system uses four types of resources:

- **Role**: Defines a set of permissions (rules) within a specific namespace. Each rule specifies API groups, resources, and verbs (actions).
- **ClusterRole**: Like a Role, but cluster-wide. It can grant access to resources across all namespaces, or to cluster-scoped resources (like nodes).
- **RoleBinding**: Grants the permissions defined in a Role to a user, group, or ServiceAccount within a specific namespace.
- **ClusterRoleBinding**: Grants the permissions defined in a ClusterRole across the entire cluster.

### ServiceAccounts and RBAC

Every pod in Kubernetes runs under a ServiceAccount. If no ServiceAccount is specified, the pod uses the `default` ServiceAccount in its namespace. ServiceAccounts are primarily used for in-cluster authentication when pods need to interact with the Kubernetes API.

The token mounted at `/var/run/secrets/kubernetes.io/serviceaccount/token` is a JWT that the API server uses to identify the ServiceAccount. However, authentication (identity) is separate from authorization (permissions). Even though the API server knows who is making the request, it denies the request unless RBAC rules explicitly grant the needed permissions.

### Roles vs ClusterRoles

| Feature | Role | ClusterRole |
|---------|------|-------------|
| Scope | Single namespace | Cluster-wide |
| Binding | RoleBinding | ClusterRoleBinding or RoleBinding |
| Use case | Namespace-scoped permissions | Cluster-wide or cross-namespace permissions |
| Resources | Namespaced resources only | All resources including cluster-scoped |

A common pattern is to define a ClusterRole with reusable permissions and then use RoleBindings in specific namespaces to grant those permissions to ServiceAccounts. This avoids duplicating Role definitions across namespaces.

### The Principle of Least Privilege

When creating RBAC rules, grant only the minimum permissions needed. In this drill, the pod only needs `get` and `list` verbs on `pods`. Granting broader permissions like `*` (all verbs) or access to all resources introduces unnecessary security risk.

### API Groups

The `apiGroups` field in a Role rule specifies which Kubernetes API group the resources belong to. Core resources like pods, services, and configmaps use the empty string `""` (the core API group). Other resources like deployments (`apps`), ingresses (`networking.k8s.io`), and roles (`rbac.authorization.k8s.io`) have their own API groups.

## Testing

Verify the Role and RoleBinding were created:

```bash
kubectl get roles
kubectl get rolebindings
```

Expected output:

```
NAME          CREATED AT
pod-reader    2024-01-01T00:00:00Z

NAME                      ROLE               AGE
app-pod-reader-binding    Role/pod-reader    10s
```

Test that the ServiceAccount can now list pods:

```bash
kubectl exec -it $(kubectl get pod -l app=api-reader -o jsonpath='{.items[0].metadata.name}') -- sh -c 'TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token) && wget -qO- --header "Authorization: Bearer $TOKEN" --no-check-certificate https://kubernetes.default.svc/api/v1/namespaces/default/pods 2>&1 | head -5'
```

Expected output (truncated):

```json
{
  "kind": "PodList",
  "apiVersion": "v1",
  "metadata": {
```

You can also use `kubectl auth can-i` to verify permissions:

```bash
kubectl auth can-i list pods --as=system:serviceaccount:default:app-service-account
```

Expected output:

```
yes
```

## Common Mistakes

- **Creating a ClusterRoleBinding when only namespace-scoped access is needed**: If the pod only needs to list pods in its own namespace, a Role and RoleBinding are sufficient. Using ClusterRoleBinding grants access to all namespaces, violating the principle of least privilege.
- **Forgetting the namespace in the RoleBinding subjects**: The `namespace` field under `subjects` must match the namespace where the ServiceAccount lives. Omitting it can cause the binding to not match the ServiceAccount correctly.
- **Using the wrong apiGroup in the Role rules**: Core resources like pods use `apiGroups: [""]` (empty string). A common mistake is to write `apiGroups: ["v1"]` or `apiGroups: ["core"]`, which are incorrect.
- **Expecting the fix to work without waiting**: RBAC changes take effect immediately in the API server, but the pod's script only queries every 30 seconds. Either wait for the next loop or exec in to test immediately.
- **Granting more permissions than needed**: Adding verbs like `create`, `delete`, or `patch` when the application only needs `get` and `list` is a security risk. Always follow the principle of least privilege.
- **Confusing Role/RoleBinding with ClusterRole/ClusterRoleBinding**: A RoleBinding can reference a ClusterRole but limits the scope to the binding's namespace. A ClusterRoleBinding grants cluster-wide access. Make sure you use the right combination for your use case.

## Additional Resources

- [Kubernetes RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [Using RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/#role-and-clusterrole)
- [Configure Service Accounts for Pods](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/)
- [Kubectl auth can-i](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_auth/kubectl_auth_can-i/)
- [RBAC Good Practices](https://kubernetes.io/docs/concepts/security/rbac-good-practices/)
