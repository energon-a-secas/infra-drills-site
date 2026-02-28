# Solution for Persistent Volume Wrong Access Mode

## The Issue

The StatefulSet `data-store` has 2 replicas, and the `volumeClaimTemplates` request 2Gi of storage with `ReadWriteOnce` access mode from the `manual` StorageClass. Two PersistentVolumes (`data-pv-0` and `data-pv-1`) were created, but they only provide 1Gi of capacity each. The PVCs request 2Gi, so the first PVC can bind to `data-pv-0` only if the capacity matches -- but since the PVs only have 1Gi and the PVCs request 2Gi, the PVCs cannot bind because the PV capacity is insufficient. If the first PVC happened to bind (in some Kubernetes versions or configurations), the second PVC will definitely fail because there is no PV with enough capacity.

The core mismatch is that the PersistentVolumes provide 1Gi of storage while the PersistentVolumeClaims request 2Gi. Additionally, because `hostPath` volumes are node-local and `ReadWriteOnce`, they present limitations in multi-replica scenarios.

## Solution

There are multiple approaches to fix this. The most straightforward is to either reduce the PVC request to match the PV capacity, or increase the PV capacity to match the PVC request.

### Approach 1: Fix the PV capacity to match the PVC request

#### Step 1: Identify the problem

Check the PVC status:

```bash
kubectl get pvc
```

You will see one or both PVCs in `Pending` state. Describe the pending PVC for details:

```bash
kubectl describe pvc data-volume-data-store-1
```

In the Events section, look for messages about no matching PV found or insufficient capacity.

Check the PV details:

```bash
kubectl get pv
```

Notice the PVs have `1Gi` capacity but the PVCs request `2Gi`.

#### Step 2: Delete the existing PVs

```bash
kubectl delete pv data-pv-0 data-pv-1
```

If a PV is bound to a PVC, you may need to delete the PVC first:

```bash
kubectl delete pvc data-volume-data-store-0 data-volume-data-store-1
```

#### Step 3: Delete the StatefulSet pods to allow fresh PVC creation

```bash
kubectl delete statefulset data-store
```

#### Step 4: Create PVs with the correct capacity

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: data-pv-0
  labels:
    type: local
spec:
  capacity:
    storage: 2Gi
  accessModes:
  - ReadWriteOnce
  hostPath:
    path: /tmp/data-store-0
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: data-pv-1
  labels:
    type: local
spec:
  capacity:
    storage: 2Gi
  accessModes:
  - ReadWriteOnce
  hostPath:
    path: /tmp/data-store-1
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
EOF
```

#### Step 5: Re-create the StatefulSet

Apply the original template (which re-creates the StatefulSet):

```bash
kubectl apply -f template.yaml
```

Or create just the StatefulSet part with the correct configuration.

#### Step 6: Verify both pods are running

```bash
kubectl get pods -l app=data-store
kubectl get pvc -l app=data-store
kubectl get pv
```

Both pods should be `Running` and both PVCs should be `Bound`.

### Approach 2: Reduce the PVC request to match PV capacity

Instead of changing the PVs, modify the StatefulSet's `volumeClaimTemplates` to request `1Gi` instead of `2Gi`:

#### Step 1: Delete the StatefulSet and PVCs

StatefulSet `volumeClaimTemplates` are immutable, so you must delete and recreate:

```bash
kubectl delete statefulset data-store
kubectl delete pvc data-volume-data-store-0 data-volume-data-store-1
```

#### Step 2: Edit the template and reapply

Edit `template.yaml` and change the storage request from `2Gi` to `1Gi`:

```yaml
  volumeClaimTemplates:
  - metadata:
      name: data-volume
    spec:
      accessModes:
      - ReadWriteOnce
      storageClassName: manual
      resources:
        requests:
          storage: 1Gi    # Changed from 2Gi to 1Gi
```

Apply the updated template:

```bash
kubectl apply -f template.yaml
```

#### Step 3: Verify both pods are running

```bash
kubectl get pods -l app=data-store
kubectl get pvc
kubectl get pv
```

### Approach 3: Use a dynamic StorageClass (Minikube)

Instead of manually creating PVs, use Minikube's built-in `standard` StorageClass which dynamically provisions volumes:

#### Step 1: Delete existing resources

```bash
kubectl delete statefulset data-store
kubectl delete pvc data-volume-data-store-0 data-volume-data-store-1
kubectl delete pv data-pv-0 data-pv-1
```

#### Step 2: Update the template to use the default StorageClass

Edit `template.yaml` and change the `storageClassName` from `manual` to `standard` (or remove it entirely to use the default):

```yaml
  volumeClaimTemplates:
  - metadata:
      name: data-volume
    spec:
      accessModes:
      - ReadWriteOnce
      storageClassName: standard
      resources:
        requests:
          storage: 1Gi
```

Remove the PersistentVolume definitions from the template (they are no longer needed since storage will be dynamically provisioned).

Apply the updated template:

```bash
kubectl apply -f template.yaml
```

## Understanding

### PersistentVolume Access Modes

PersistentVolumes in Kubernetes support three access modes:

| Access Mode | Abbreviation | Description |
|-------------|-------------|-------------|
| ReadWriteOnce | RWO | The volume can be mounted as read-write by a single node |
| ReadOnlyMany | ROX | The volume can be mounted as read-only by many nodes |
| ReadWriteMany | RWX | The volume can be mounted as read-write by many nodes |

**Important**: `ReadWriteOnce` restricts access to a single **node**, not a single pod. Multiple pods on the same node can mount a RWO volume. However, once a RWO volume is bound to a node, pods on other nodes cannot use it.

### PV and PVC Binding

For a PVC to bind to a PV, several conditions must match:

1. **Storage capacity**: The PV must have at least as much capacity as the PVC requests. A PVC requesting 2Gi will not bind to a PV with only 1Gi.
2. **Access modes**: The PV must support the access modes requested by the PVC.
3. **StorageClass**: The PV and PVC must have the same `storageClassName` (or both be empty).
4. **Volume mode**: The PV and PVC must have the same volume mode (Filesystem or Block).
5. **Selectors**: If the PVC has label selectors, the PV must match them.

### StatefulSet Volume Behavior

StatefulSets handle storage differently from Deployments:

- **volumeClaimTemplates**: Each replica gets its own PVC created from the template. For a StatefulSet with 2 replicas and a template named `data-volume`, Kubernetes creates `data-volume-data-store-0` and `data-volume-data-store-1`.
- **Stable identity**: PVCs are tied to specific pod ordinals. `data-store-0` always uses `data-volume-data-store-0`.
- **PVC retention**: By default, PVCs are NOT deleted when the StatefulSet is deleted or scaled down. This preserves data across restarts. You must manually delete PVCs to release the associated PVs.
- **Ordered creation**: Pods are created sequentially (0, then 1, then 2...). If pod 0's PVC cannot bind, pod 1 will not be created. If pod 0 succeeds but pod 1's PVC cannot bind, pod 1 remains Pending.

### hostPath Volumes and Their Limitations

`hostPath` volumes use a directory on the host node's filesystem. They have significant limitations:

- **Node-local**: The data is only available on the specific node where the volume was created.
- **Not portable**: If a pod is rescheduled to a different node, it cannot access the data.
- **Not suitable for multi-replica**: In a multi-node cluster, multiple pods using hostPath may write to different directories on different nodes, losing data consistency.
- **Security risk**: hostPath volumes can expose the host filesystem to containers.

In Minikube (single node), hostPath works because all pods run on the same node. In multi-node clusters, you need a proper storage solution (NFS, cloud block storage, Ceph, etc.).

### Storage Classes and Dynamic Provisioning

StorageClasses define "classes" of storage with different performance, backup, or replication characteristics. When a PVC references a StorageClass that supports dynamic provisioning, Kubernetes automatically creates a PV to satisfy the claim. This eliminates the need to manually create PVs.

Minikube ships with a `standard` StorageClass that dynamically provisions hostPath-based volumes. In production clusters, cloud providers offer StorageClasses backed by their block storage services (e.g., AWS EBS, GCP Persistent Disk, Azure Disk).

## Testing

After applying the fix, verify all resources are healthy:

```bash
kubectl get pods -l app=data-store
```

Expected output:

```
NAME           READY   STATUS    RESTARTS   AGE
data-store-0   1/1     Running   0          60s
data-store-1   1/1     Running   0          30s
```

Check PVC status:

```bash
kubectl get pvc
```

Expected output:

```
NAME                         STATUS   VOLUME      CAPACITY   ACCESS MODES   STORAGECLASS   AGE
data-volume-data-store-0     Bound    data-pv-0   2Gi        RWO            manual         60s
data-volume-data-store-1     Bound    data-pv-1   2Gi        RWO            manual         30s
```

Check PV status:

```bash
kubectl get pv
```

Expected output:

```
NAME        CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                              STORAGECLASS   AGE
data-pv-0   2Gi        RWO            Retain           Bound    default/data-volume-data-store-0   manual         2m
data-pv-1   2Gi        RWO            Retain           Bound    default/data-volume-data-store-1   manual         2m
```

Verify both pods can write to their volumes:

```bash
kubectl exec data-store-0 -- cat /data/log.txt
kubectl exec data-store-1 -- cat /data/log.txt
```

Both pods should show their hostname and timestamps in the log.

## Common Mistakes

- **Trying to edit volumeClaimTemplates in place**: StatefulSet `volumeClaimTemplates` are immutable after creation. You must delete the StatefulSet (and potentially the PVCs) and recreate it with the updated template. Use `kubectl delete statefulset data-store --cascade=orphan` to delete the StatefulSet without deleting the pods, if you want to minimize downtime.
- **Forgetting to delete old PVCs**: When recreating a StatefulSet, old PVCs may still exist and be in a `Pending` or `Lost` state. These stale PVCs can prevent new PVCs from binding to the correct PVs. Always clean up PVCs when changing volume configurations.
- **Confusing PV capacity with actual disk space**: A PV's `capacity` field is a label used for matching with PVCs. For hostPath volumes, it does not actually enforce any disk quota. However, the matching logic still requires the PV capacity to be >= the PVC request.
- **Assuming ReadWriteOnce means single-pod access**: RWO means single-node access. Multiple pods on the same node can mount a RWO volume simultaneously. If you need to restrict access to a single pod, you must use application-level locking.
- **Not checking StorageClass compatibility**: The PV and PVC must use the same StorageClass name. A PVC with `storageClassName: manual` will never bind to a PV with `storageClassName: standard`, even if capacity and access modes match.
- **Deleting PVs with Retain reclaim policy and expecting automatic cleanup**: When a PV has `persistentVolumeReclaimPolicy: Retain`, deleting the PVC does not delete the PV or its data. The PV transitions to `Released` state and must be manually cleaned up or patched to be reusable.

## Additional Resources

- [Kubernetes Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [Kubernetes Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/)
- [StatefulSet Basics](https://kubernetes.io/docs/tutorials/stateful-application/basic-stateful-set/)
- [Configure a Pod to Use a PersistentVolume](https://kubernetes.io/docs/tasks/configure-pod-container/configure-persistent-volume-storage/)
- [Persistent Volume Access Modes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#access-modes)
- [Minikube Persistent Volumes](https://minikube.sigs.k8s.io/docs/handbook/persistent_volumes/)
