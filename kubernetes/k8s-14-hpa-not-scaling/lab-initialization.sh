kubectl apply -f template.yaml

echo ""
echo "Lab initialized. The HPA, Deployment, and Service have been created."
echo ""
echo "To generate load against the service, run:"
echo "  kubectl run load-generator --image=busybox:1.36 --restart=Never -- /bin/sh -c 'while true; do wget -q -O- http://web-app; done'"
echo ""
echo "Then watch the HPA with:"
echo "  kubectl get hpa web-app-hpa -w"
echo ""
echo "The HPA should scale the Deployment, but it does not. Investigate why."
