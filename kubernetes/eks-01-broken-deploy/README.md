## Problem

A deployment was applied to the cluster but the application is not working as expected.

### Context
- The deployment YAML was copied from a working example
- The application should be accessible once deployed

### Hint
Compare the deployment manifest carefully with the working version in `eks-00-ingress`.

## Validation

```bash
kubectl get pods
# All pods should be Running
kubectl get deployments
# Deployment should show desired replicas as available
```

## [Solution](../solutions/eks-01-broken-deploy.md)
