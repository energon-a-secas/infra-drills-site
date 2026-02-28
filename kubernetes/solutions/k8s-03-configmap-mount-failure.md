# Solution for ConfigMap Mount Failure

## The Issue

The deployment references a ConfigMap named `app-config` as a volume, but this ConfigMap does not exist in the cluster. When Kubernetes tries to create the container, it cannot mount the volume because the referenced ConfigMap is missing. The pod remains stuck in `ContainerCreating` status indefinitely because the kubelet cannot proceed with container setup until all volumes are satisfied.

## Solution

Create the missing ConfigMap that the deployment expects, then verify the pod transitions to `Running`.

### Step 1: Identify the problem

```bash
kubectl get pods -l app=web-app
```

You will see the pod stuck in `ContainerCreating`. Get more details:

```bash
kubectl describe pod -l app=web-app
```

In the Events section, look for:

```
Warning  FailedMount  ...  MountVolume.SetUp failed for volume "config-volume" : configmap "app-config" not found
```

### Step 2: Create the missing ConfigMap

Create the `app-config` ConfigMap with a valid nginx configuration file:

```bash
kubectl create configmap app-config --from-literal=default.conf='server {
    listen 80;
    server_name localhost;

    location / {
        root   /usr/share/nginx/html;
        index  index.html index.htm;
    }
}'
```

Alternatively, create it from a YAML manifest:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  default.conf: |
    server {
        listen 80;
        server_name localhost;

        location / {
            root   /usr/share/nginx/html;
            index  index.html index.htm;
        }
    }
```

Apply with:

```bash
kubectl apply -f configmap.yaml
```

### Step 3: Wait for the pod to start

Once the ConfigMap exists, the kubelet will automatically mount the volume and start the container. The pod should transition to `Running` within a few seconds:

```bash
kubectl get pods -l app=web-app -w
```

## Understanding

### ConfigMaps

ConfigMaps are Kubernetes objects that store non-confidential configuration data as key-value pairs. They decouple configuration from container images, making applications portable. ConfigMaps can be consumed as:

- **Environment variables**: Injected into container env vars.
- **Command-line arguments**: Used in container commands.
- **Volume mounts**: Mounted as files inside the container filesystem.

### Volume Mounts with ConfigMaps

When a ConfigMap is mounted as a volume, each key in the ConfigMap becomes a file in the mount directory. In this drill, the key `default.conf` becomes the file `/etc/nginx/conf.d/default.conf` inside the container.

### Why ContainerCreating?

Unlike image pull errors (which show `ErrImagePull`) or crash loops (which show `CrashLoopBackOff`), a missing volume source prevents the container from even being created. The kubelet keeps retrying the mount operation, and the pod stays in `ContainerCreating` until the volume source becomes available or a timeout occurs.

## Testing

After creating the ConfigMap, verify the pod is running:

```bash
kubectl get pods -l app=web-app
```

Expected output:

```
NAME                       READY   STATUS    RESTARTS   AGE
web-app-xxxxxxxxx-xxxxx    1/1     Running   0          45s
```

Verify the ConfigMap is mounted correctly:

```bash
kubectl exec -it $(kubectl get pod -l app=web-app -o jsonpath='{.items[0].metadata.name}') -- cat /etc/nginx/conf.d/default.conf
```

Test that nginx is serving requests:

```bash
kubectl port-forward deployment/web-app 8080:80
curl localhost:8080
```

## Common Mistakes

- **Creating the ConfigMap in the wrong namespace**: The ConfigMap must exist in the same namespace as the pod. If the deployment is in `default` namespace, the ConfigMap must also be in `default`.
- **Wrong ConfigMap key name**: If the application expects a specific filename (e.g., `default.conf`), the ConfigMap key must match. A key named `config` would create a file called `config` instead of `default.conf`.
- **Using `optional: true` as a blanket fix**: While setting `configMap.optional: true` in the volume definition prevents the pod from getting stuck, it means the application starts without its configuration, which may cause runtime errors or unexpected behavior.
- **Forgetting that ConfigMap updates are not instant**: When you update a ConfigMap, mounted volumes are eventually updated (kubelet sync period, typically ~1 minute), but environment variables are NOT updated until the pod is restarted.

## Additional Resources

- [Kubernetes ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/)
- [Configure a Pod to Use a ConfigMap](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/)
- [Kubernetes Volumes](https://kubernetes.io/docs/concepts/storage/volumes/#configmap)
