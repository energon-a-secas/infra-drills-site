kubectl apply -f template.yaml
echo "Waiting for first StatefulSet pod to be ready..."
kubectl wait --for=condition=ready pod/data-store-0 --timeout=90s 2>/dev/null || true
echo ""
echo "Lab ready. The StatefulSet has 2 replicas but the second pod is stuck Pending."
echo "Check status with: kubectl get pods -l app=data-store"
echo "Check PVCs with: kubectl get pvc"
echo "Check PVs with: kubectl get pv"
