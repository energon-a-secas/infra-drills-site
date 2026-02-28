# eks-01-broken-deploy

## The Issue

The deployment YAML in `eks-01-broken-deploy/` was copied from the working example in `eks-00-ingress/`, but only the `deployment.yaml` file was copied -- the `service.yaml` and `ingress.yaml` were not. The lab initialization script (`lab-initialization.sh`) only runs `kubectl apply -f deployment.yaml`, whereas the working example applies the deployment, a Service, and an Ingress.

The result is that the pods start and run successfully (the Deployment itself is valid), but the application is **not accessible** from outside the cluster. Without a Service, there is no stable network endpoint to reach the pods. Without an Ingress, there is no external HTTP routing. The deployment "works" at the pod level but the application is not working as expected because no one can reach it.

Comparing the two `lab-initialization.sh` files makes this clear:

**Working (`eks-00-ingress/lab-initialization.sh`):**
```bash
minikube addons enable ingress
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f ingress.yaml
```

**Broken (`eks-01-broken-deploy/lab-initialization.sh`):**
```bash
kubectl apply -f deployment.yaml
```

## Solution

Create the missing Service and Ingress resources to expose the application.

### Step 1: Verify the Deployment is Running

First, confirm that the pods are actually running. The deployment itself is not broken:

```bash
kubectl get deployments
kubectl get pods -l app=nginx
```

You should see 2/2 pods in `Running` state. The deployment is healthy.

### Step 2: Try to Access the Application

Attempt to reach the application to confirm the problem:

```bash
# No service exists
kubectl get svc
# You will not see an nginx-service

# No ingress exists
kubectl get ingress
# You will not see an example-ingress
```

### Step 3: Create the Service

Create a `service.yaml` file to expose the nginx pods:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
spec:
  selector:
    app: nginx
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
  type: NodePort
```

Apply it:

```bash
kubectl apply -f service.yaml
```

The Service uses a label selector (`app: nginx`) that matches the labels on the pods created by the Deployment. The `NodePort` type makes the service accessible on a port on each cluster node.

### Step 4: Verify the Service

```bash
kubectl get svc nginx-service
```

You should see the service with a `ClusterIP` and an assigned `NodePort`.

### Step 5: Access the Application via Service

```bash
minikube service nginx-service --url
```

This returns a URL you can use to access nginx. Test it:

```bash
curl $(minikube service nginx-service --url)
```

You should receive the default nginx welcome page HTML.

### Step 6 (Optional): Add Ingress for HTTP Routing

If you also want to replicate the full working setup with Ingress:

```bash
minikube addons enable ingress
```

Create an `ingress.yaml` file:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: hello-world.info
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: nginx-service
            port:
              number: 80
```

Apply it:

```bash
kubectl apply -f ingress.yaml
```

Then add the hostname to `/etc/hosts` and test:

```bash
echo "$(minikube ip) hello-world.info" | sudo tee -a /etc/hosts
curl http://hello-world.info
```

## Understanding

### Kubernetes Networking Model

A Kubernetes cluster has several layers of networking, and each Kubernetes resource type addresses a different layer:

**Pods** have their own IP addresses within the cluster, but these IPs are ephemeral. When a pod is deleted and recreated (during a rolling update, scaling event, or crash recovery), it gets a new IP. You should never try to reach pods by their IP addresses directly.

**Services** provide a stable virtual IP (ClusterIP) and DNS name that load-balances across all pods matching a label selector. Services solve the pod discovery problem -- instead of tracking individual pod IPs, you connect to the Service, which always routes to healthy pods. Service types include:
- `ClusterIP` (default) -- Accessible only within the cluster
- `NodePort` -- Accessible on a static port on each node's IP
- `LoadBalancer` -- Provisions an external load balancer (in cloud environments)

**Ingress** provides HTTP/HTTPS routing from outside the cluster to Services inside the cluster. It enables host-based and path-based routing, TLS termination, and other L7 features. An Ingress requires an Ingress Controller to be running in the cluster (in Minikube, this is the `ingress` addon).

### Why a Deployment Alone Is Not Enough

A Deployment manages pods -- it ensures the desired number of replicas are running and handles rolling updates. But a Deployment does not provide any mechanism for accessing those pods from outside the cluster (or even reliably from inside the cluster). The Deployment is responsible for **running** the application; the Service and Ingress are responsible for **exposing** it.

This is by design -- Kubernetes separates concerns. You can have a Deployment without a Service (for batch jobs or workers that do not need incoming traffic), or multiple Services pointing to the same Deployment (for different access patterns).

### Label Selectors: The Glue Between Resources

The connection between a Service and a Deployment's pods is made through label selectors, not by name or direct reference:

```
Deployment spec.template.metadata.labels: app: nginx
                         |
                         v  (label match)
Service spec.selector: app: nginx
                         |
                         v  (service name match)
Ingress spec.rules[].backend.service.name: nginx-service
```

If any of these links are broken (mismatched labels, wrong service name), traffic will not flow even if all resources exist.

## Testing

1. Start with a clean state:

```bash
kubectl delete deployment nginx-deployment 2>/dev/null
kubectl delete svc nginx-service 2>/dev/null
kubectl delete ingress example-ingress 2>/dev/null
```

2. Apply only the deployment (reproducing the broken state):

```bash
kubectl apply -f deployment.yaml
```

3. Verify pods are running but nothing is accessible:

```bash
kubectl get pods -l app=nginx
# Should show 2 running pods

kubectl get svc
# Should NOT show nginx-service

kubectl get ingress
# Should NOT show example-ingress
```

4. Apply the Service fix:

```bash
kubectl apply -f service.yaml
```

5. Verify the application is now accessible:

```bash
kubectl get svc nginx-service
# Should show the service with a NodePort

minikube service nginx-service --url
# Should return a reachable URL

curl $(minikube service nginx-service --url)
# Should return nginx welcome page
```

6. Verify the deployment shows desired replicas as available:

```bash
kubectl get deployments
# Should show 2/2 READY
```

## Common Mistakes

1. **Assuming the Deployment is broken because the app does not work** -- The first instinct is to look for errors in the Deployment manifest (wrong image, bad ports, misconfigured probes). But in this drill, the Deployment is perfectly fine. The issue is the missing Service. Always check `kubectl get svc` and `kubectl get ingress` alongside `kubectl get pods`
2. **Creating a Service with the wrong selector labels** -- The Service's `spec.selector` must match the pod's `metadata.labels` exactly. If the Deployment uses `app: nginx` but the Service uses `app: web-server`, no pods will match and the Service will have no endpoints. Verify with `kubectl get endpoints nginx-service`
3. **Using `ClusterIP` type and wondering why it is not externally accessible** -- The default Service type is `ClusterIP`, which is only reachable from within the cluster. For external access in Minikube, use `NodePort` or `LoadBalancer`. The working example uses `NodePort`
4. **Forgetting to enable the Ingress addon in Minikube** -- The Ingress resource requires an Ingress Controller. In Minikube, you must run `minikube addons enable ingress` before Ingress resources will function. Without the controller, the Ingress resource is created but has no effect
5. **Not matching the Service port with the container port** -- The Service's `targetPort` must match the container's `containerPort` (80 for nginx). The Service's `port` can be any value you choose for external access, but `targetPort` must match what the container listens on
6. **Only comparing the deployment.yaml files** -- Since both `deployment.yaml` files are identical, a diff will show no differences. The real comparison should be between the entire directory contents and the lab initialization scripts, which reveal the missing Service and Ingress

## Additional Resources

- [Kubernetes Services Documentation](https://kubernetes.io/docs/concepts/services-networking/service/)
- [Kubernetes Ingress Documentation](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [Connecting Applications with Services](https://kubernetes.io/docs/tutorials/services/connect-applications-service/)
- [Minikube Accessing Apps](https://minikube.sigs.k8s.io/docs/handbook/accessing/)
- [Minikube Ingress Addon](https://kubernetes.io/docs/tasks/access-application-cluster/ingress-minikube/)
- [Debugging Services](https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/)
