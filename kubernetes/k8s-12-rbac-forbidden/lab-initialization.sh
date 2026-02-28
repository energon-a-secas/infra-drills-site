kubectl apply -f template.yaml
echo "Waiting for api-reader pod to be ready..."
kubectl wait --for=condition=ready pod -l app=api-reader --timeout=60s
echo ""
echo "Lab ready. The pod's ServiceAccount gets 403 Forbidden when calling the Kubernetes API."
echo "Try: kubectl logs \$(kubectl get pod -l app=api-reader -o jsonpath='{.items[0].metadata.name}')"
