# Problem/Request

A StatefulSet has 2 replicas but only 1 pod starts successfully. The second pod is stuck in `Pending` state and cannot mount its volume.

* Context: A StatefulSet named `data-store` was deployed with `volumeClaimTemplates` to provide persistent storage to each replica. The first pod started fine and its PersistentVolumeClaim is bound. However, the second pod remains `Pending` and its PVC cannot be satisfied. A PersistentVolume was manually created with `hostPath` storage.
* Hint: Check the PVC events with `kubectl describe pvc` and look at the PV access modes with `kubectl get pv`. The `ReadWriteOnce` access mode means the volume can only be mounted by a single node.

# Validation

To validate the solution, verify that both replicas are running:

```
kubectl get pods -l app=data-store
kubectl get pvc -l app=data-store
```

Both pods should show `Running` status with `1/1` containers ready, and both PVCs should show `Bound` status.

Solution: [../solutions/k8s-20-persistent-volume-wrong-access-mode.md](../solutions/k8s-20-persistent-volume-wrong-access-mode.md)
