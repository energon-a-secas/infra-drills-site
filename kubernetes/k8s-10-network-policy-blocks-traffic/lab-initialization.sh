kubectl apply -f template.yaml
echo "Waiting for backend pod to be ready..."
kubectl wait --for=condition=ready pod -l app=backend --timeout=60s
echo "Waiting for frontend pod to be ready..."
kubectl wait --for=condition=ready pod -l app=frontend --timeout=60s
echo ""
echo "Lab ready. The frontend pod cannot reach the backend service."
echo "Try: kubectl exec -it \$(kubectl get pod -l app=frontend -o jsonpath='{.items[0].metadata.name}') -- wget -qO- --timeout=5 http://backend"
