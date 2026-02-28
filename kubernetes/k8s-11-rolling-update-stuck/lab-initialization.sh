echo "Deploying web-server with nginx:1.24 (working version)..."
kubectl apply -f template.yaml
echo "Waiting for rollout to complete..."
kubectl rollout status deployment/web-server --timeout=120s
echo ""
echo "Triggering broken update with nonexistent image tag..."
kubectl set image deployment/web-server nginx=nginx:nonexistent --record
echo ""
echo "Lab ready. The rolling update is stuck."
echo "Check status with: kubectl rollout status deployment/web-server"
echo "Check pods with: kubectl get pods -l app=web-server"
