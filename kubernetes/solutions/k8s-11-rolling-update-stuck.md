# Solution for Rolling Update Stuck

## The Issue

The deployment `web-server` was updated to use the image `nginx:nonexistent`, which does not exist in any container registry. The rolling update strategy creates new pods with the new image, but those pods fail to pull the image and enter `ImagePullBackOff` status. Because of the `maxUnavailable: 1` setting, Kubernetes keeps at least 2 of the original 3 pods running to maintain availability, so the old pods continue serving traffic. However, the rollout can never complete because the new pods can never become ready, leaving the deployment in a stuck state.

## Solution

There are two approaches to fix this: roll back to the previous working version, or correct the image tag to a valid one.

### Approach 1: Rollback using rollout undo

#### Step 1: Identify the problem

Check the rollout status:

```bash
kubectl rollout status deployment/web-server
```

This will show the rollout is waiting and not progressing. Check the pods:

```bash
kubectl get pods -l app=web-server
```

You will see a mix of `Running` pods (old version) and `ImagePullBackOff`/`ErrImagePull` pods (new version).

Describe one of the failing pods to confirm the image issue:

```bash
kubectl describe pod $(kubectl get pod -l app=web-server --field-selector=status.phase!=Running -o jsonpath='{.items[0].metadata.name}')
```

In the Events section, look for:

```
Warning  Failed     ...  Failed to pull image "nginx:nonexistent": ... not found
Warning  Failed     ...  Error: ErrImagePull
Normal   BackOff    ...  Back-off pulling image "nginx:nonexistent"
Warning  Failed     ...  Error: ImagePullBackOff
```

#### Step 2: Check rollout history

```bash
kubectl rollout history deployment/web-server
```

This shows the revision history. The previous revision had the working image `nginx:1.24`.

#### Step 3: Roll back to the previous version

```bash
kubectl rollout undo deployment/web-server
```

This reverts the deployment to the last successful revision.

#### Step 4: Verify the rollback

```bash
kubectl rollout status deployment/web-server
```

Wait for it to report `successfully rolled out`, then verify all pods:

```bash
kubectl get pods -l app=web-server
```

All 3 pods should be `Running` with `1/1` ready.

### Approach 2: Fix the image tag

Instead of rolling back, you can correct the image to a valid tag:

```bash
kubectl set image deployment/web-server nginx=nginx:1.25
```

Or edit the deployment directly:

```bash
kubectl edit deployment web-server
```

Change `image: nginx:nonexistent` to a valid tag like `nginx:1.25`, then save and exit.

Verify the rollout completes:

```bash
kubectl rollout status deployment/web-server
```

## Understanding

### Rolling Updates

The RollingUpdate strategy is the default deployment strategy in Kubernetes. It gradually replaces old pods with new ones, ensuring that some pods are always available during the update. Two parameters control the behavior:

- **maxUnavailable**: The maximum number of pods that can be unavailable during the update. With `maxUnavailable: 1` and 3 replicas, at least 2 pods must always be running.
- **maxSurge**: The maximum number of extra pods that can be created above the desired count. With `maxSurge: 1` and 3 replicas, up to 4 pods can exist during the update.

### Why the Update Gets Stuck

During a rolling update, Kubernetes creates new pods with the updated spec. If the new pods cannot become ready (due to image pull failures, crash loops, failing readiness probes, etc.), the rollout controller stops progressing. It will not terminate more old pods because that would violate the `maxUnavailable` constraint. The deployment remains in this partially-updated state indefinitely until the issue is resolved or the deployment is rolled back.

### Rollout History and Undo

Kubernetes maintains a revision history for deployments (controlled by `spec.revisionHistoryLimit`, default 10). Each change to the pod template creates a new revision stored as a ReplicaSet. The `kubectl rollout undo` command switches the deployment back to the previous revision's pod template.

You can also roll back to a specific revision:

```bash
kubectl rollout undo deployment/web-server --to-revision=1
```

### The --record Flag

The `--record` flag (used in the lab initialization) annotates the deployment with the command that caused the change. This makes the rollout history more informative. Note that `--record` is deprecated in newer Kubernetes versions in favor of other annotation approaches.

## Testing

After applying the fix, verify the deployment is healthy:

```bash
kubectl rollout status deployment/web-server
```

Expected output:

```
deployment "web-server" successfully rolled out
```

Check all pods are running:

```bash
kubectl get pods -l app=web-server
```

Expected output:

```
NAME                          READY   STATUS    RESTARTS   AGE
web-server-xxxxxxxxx-xxxxx    1/1     Running   0          30s
web-server-xxxxxxxxx-xxxxx    1/1     Running   0          28s
web-server-xxxxxxxxx-xxxxx    1/1     Running   0          26s
```

Verify the image is correct:

```bash
kubectl get deployment web-server -o jsonpath='{.spec.template.spec.containers[0].image}'
```

Expected output (if rolled back):

```
nginx:1.24
```

## Common Mistakes

- **Waiting indefinitely for the rollout to fix itself**: A stuck rollout due to a bad image will never self-resolve. The image tag does not exist, so no amount of backoff retries will succeed. You must either fix the image or roll back.
- **Deleting individual failing pods**: Deleting the `ImagePullBackOff` pods does not fix the problem. The deployment controller will immediately create new pods with the same broken image tag.
- **Using `kubectl rollout restart` instead of `kubectl rollout undo`**: A rollout restart recreates all pods but uses the CURRENT deployment spec, which still has the bad image. You need `rollout undo` to revert the spec to the previous version, or `set image` to specify a valid image.
- **Not checking rollout history before undoing**: If there have been multiple updates, `rollout undo` goes back to the immediately previous revision, which may not be the one you want. Always check `rollout history` first.
- **Forgetting to verify the image tag exists**: Before updating a deployment, verify the image and tag exist in the registry. Use `docker pull nginx:1.25` or check the registry directly.

## Additional Resources

- [Kubernetes Deployments - Updating a Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#updating-a-deployment)
- [Kubernetes Deployments - Rolling Back](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#rolling-back-a-deployment)
- [Managing Resources - Rolling Update](https://kubernetes.io/docs/tutorials/kubernetes-basics/update/update-intro/)
- [kubectl rollout](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_rollout/)
