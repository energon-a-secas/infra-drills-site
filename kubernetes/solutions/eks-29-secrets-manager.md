# eks-29-secrets-manager

## The Issue

The deployment `my-app` in `deployment.yaml` references a Kubernetes Secret named `aws-secrets` via `secretKeyRef`:

```yaml
env:
  - name: MY_SECRET
    valueFrom:
      secretKeyRef:
        name: aws-secrets
        key: MY_SECRET
```

However, no Kubernetes Secret named `aws-secrets` exists in the cluster. When you apply this deployment, the pod enters a `CreateContainerConfigError` state because Kubernetes cannot find the referenced Secret to inject the environment variable.

In a production EKS environment, this Secret would be automatically created and synced by the **AWS Secrets Manager CSI Driver** (also called the Secrets Store CSI Driver with the AWS provider). The CSI driver mounts secrets from AWS Secrets Manager into pods as volumes and can optionally sync them to Kubernetes Secrets. But on minikube, there is no real AWS Secrets Manager integration available, so the Secret must be created manually.

## Solution

### Step 1: Verify the Problem

Apply the deployment and observe the error:

```bash
kubectl apply -f deployment.yaml
kubectl get pods -l app=my-app
```

You will see the pod stuck in `CreateContainerConfigError`. Describe the pod to confirm:

```bash
kubectl describe pod -l app=my-app
```

In the Events section, you will see:

```
Warning  Failed  Error: secret "aws-secrets" not found
```

### Step 2: Create the Kubernetes Secret Manually

Since we are running on minikube without the AWS Secrets Manager CSI driver, we create the Secret that the deployment expects:

```bash
kubectl create secret generic aws-secrets \
  --from-literal=MY_SECRET='my-super-secret-value'
```

Or as a YAML manifest:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: aws-secrets
type: Opaque
data:
  MY_SECRET: bXktc3VwZXItc2VjcmV0LXZhbHVl   # base64 of "my-super-secret-value"
```

Apply it:

```bash
kubectl apply -f secret.yaml
```

### Step 3: Restart the Deployment

If the pod is still stuck in `CreateContainerConfigError`, delete it so the deployment creates a new one that picks up the now-existing Secret:

```bash
kubectl delete pod -l app=my-app
```

The deployment controller will create a new pod automatically. Alternatively, you can restart the deployment:

```bash
kubectl rollout restart deployment my-app
```

### Step 4: Verify the Pod Starts

```bash
kubectl get pods -l app=my-app
```

The pod should now be in `Running` state (or `ImagePullBackOff` if `my-app-image` is not a real image -- but the Secret error is resolved).

### Step 5: Verify the Environment Variable

If the pod is running, confirm the secret was injected:

```bash
kubectl exec -it $(kubectl get pod -l app=my-app -o jsonpath='{.items[0].metadata.name}') -- env | grep MY_SECRET
```

You should see `MY_SECRET=my-super-secret-value`.

## Understanding

### How It Works in Production EKS

In a real EKS environment, you would not manually create Kubernetes Secrets. Instead, the flow involves three components working together:

#### 1. AWS Secrets Manager

AWS Secrets Manager stores the actual secret values (database passwords, API keys, etc.) as encrypted key-value pairs in the AWS cloud. Secrets are versioned, can be rotated automatically, and access is controlled via IAM policies.

```bash
# Create a secret in AWS Secrets Manager
aws secretsmanager create-secret \
  --name my-app/secrets \
  --secret-string '{"MY_SECRET":"production-secret-value"}'
```

#### 2. Secrets Store CSI Driver

The [Secrets Store CSI Driver](https://secrets-store-csi-driver.sigs.k8s.io/) is a Kubernetes CSI (Container Storage Interface) driver that allows mounting secrets from external secret stores as volumes in pods. It is provider-agnostic -- it works with AWS, Azure, GCP, and HashiCorp Vault through provider plugins.

Install the CSI driver and AWS provider:

```bash
# Install the Secrets Store CSI Driver
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
helm install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver \
  --namespace kube-system \
  --set syncSecret.enabled=true

# Install the AWS provider
kubectl apply -f https://raw.githubusercontent.com/aws/secrets-store-csi-driver-provider-aws/main/deployment/aws-provider-installer.yaml
```

#### 3. SecretProviderClass

A `SecretProviderClass` is a custom resource that tells the CSI driver which secrets to fetch and how to map them:

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: aws-secrets-provider
spec:
  provider: aws
  parameters:
    objects: |
      - objectName: "my-app/secrets"
        objectType: "secretsmanager"
        jmesPath:
          - path: MY_SECRET
            objectAlias: MY_SECRET
  secretObjects:                        # This syncs to a K8s Secret
    - secretName: aws-secrets           # The K8s Secret name the deployment references
      type: Opaque
      data:
        - objectName: MY_SECRET
          key: MY_SECRET
```

#### 4. Pod Configuration with CSI Volume

The deployment would be updated to mount the CSI volume, which triggers the secret fetch and K8s Secret sync:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      serviceAccountName: my-app-sa    # Must have IAM role with Secrets Manager access
      containers:
      - name: my-app
        image: my-app-image
        env:
          - name: MY_SECRET
            valueFrom:
              secretKeyRef:
                name: aws-secrets
                key: MY_SECRET
        volumeMounts:
          - name: secrets-store
            mountPath: "/mnt/secrets"
            readOnly: true
      volumes:
        - name: secrets-store
          csi:
            driver: secrets-store.csi.k8s.io
            readOnly: true
            volumeAttributes:
              secretProviderClass: aws-secrets-provider
```

#### 5. IAM Roles for Service Accounts (IRSA)

The pod's service account must be associated with an IAM role that has permission to read the secret from AWS Secrets Manager. This is done through EKS IAM Roles for Service Accounts (IRSA):

```bash
# Create IAM policy
aws iam create-policy \
  --policy-name my-app-secrets-policy \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"],
      "Resource": "arn:aws:secretsmanager:us-east-1:123456789012:secret:my-app/secrets-*"
    }]
  }'

# Associate with EKS service account
eksctl create iamserviceaccount \
  --name my-app-sa \
  --namespace default \
  --cluster my-cluster \
  --attach-policy-arn arn:aws:iam::123456789012:policy/my-app-secrets-policy \
  --approve
```

### The Full Production Flow

```
AWS Secrets Manager (stores actual secrets)
        |
        v  (CSI driver fetches on pod mount)
SecretProviderClass (defines mapping)
        |
        v  (syncSecret.enabled=true)
Kubernetes Secret "aws-secrets" (auto-created/synced)
        |
        v  (secretKeyRef)
Pod env var MY_SECRET
```

The key insight is that the `secretKeyRef` in the deployment is the **last step** in a chain. The Kubernetes Secret it references is not created manually -- it is created and kept in sync by the CSI driver whenever a pod mounts the corresponding `SecretProviderClass` volume.

### Why the Manual Workaround Works for Local Development

On minikube, we skip the entire CSI driver chain and create the Kubernetes Secret directly. This gives the pod the environment variable it needs. The deployment YAML does not need to change -- it only references the Kubernetes Secret, not AWS Secrets Manager directly. This separation of concerns is what makes the workaround possible.

## Testing

1. Start from a clean state:

```bash
kubectl delete deployment my-app 2>/dev/null
kubectl delete secret aws-secrets 2>/dev/null
```

2. Apply the deployment without the secret (reproduce the failure):

```bash
kubectl apply -f deployment.yaml
kubectl get pods -l app=my-app
```

You should see `CreateContainerConfigError`.

3. Confirm the error:

```bash
kubectl describe pod -l app=my-app | grep -A 3 "Warning"
```

You should see `secret "aws-secrets" not found`.

4. Create the secret:

```bash
kubectl create secret generic aws-secrets --from-literal=MY_SECRET='my-super-secret-value'
```

5. Delete the stuck pod so a new one picks up the secret:

```bash
kubectl delete pod -l app=my-app
```

6. Verify the new pod starts (note: the image `my-app-image` does not exist, so the pod will enter `ImagePullBackOff` -- but the Secret error is gone):

```bash
kubectl describe pod -l app=my-app | grep -A 3 "Warning"
```

You should no longer see `secret "aws-secrets" not found`. If you want a fully running pod, change the image to something real like `nginx` first.

7. (Optional) To test end-to-end with a real image:

```bash
kubectl delete deployment my-app
kubectl create secret generic aws-secrets --from-literal=MY_SECRET='my-super-secret-value' --dry-run=client -o yaml | kubectl apply -f -

# Patch deployment to use nginx
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: my-app
        image: nginx
        env:
          - name: MY_SECRET
            valueFrom:
              secretKeyRef:
                name: aws-secrets
                key: MY_SECRET
EOF

kubectl exec -it $(kubectl get pod -l app=my-app -o jsonpath='{.items[0].metadata.name}') -- env | grep MY_SECRET
```

## Common Mistakes

1. **Applying the deployment without creating the Secret first** -- This is the core issue. Kubernetes will not start a pod if it references a Secret that does not exist (unless the `secretKeyRef` is marked as `optional: true`). Always ensure referenced Secrets exist before deploying.
2. **Forgetting the `secretObjects` section in the SecretProviderClass** -- In production, the CSI driver mounts secrets as files in a volume. To also create a Kubernetes Secret (needed for `secretKeyRef` in env vars), you must include the `secretObjects` section. Without it, the pod gets the volume mount but the Kubernetes Secret is never created.
3. **Not mounting the CSI volume** -- The Kubernetes Secret sync only happens when a pod actually mounts the CSI volume. If no pod mounts the `SecretProviderClass`, the Kubernetes Secret is never created. This means at least one pod must have the `volumes` and `volumeMounts` configuration.
4. **Wrong IAM permissions** -- The service account's IAM role must have `secretsmanager:GetSecretValue` and `secretsmanager:DescribeSecret` permissions on the specific secret ARN. A missing or overly broad policy will cause authentication failures at the CSI driver level.
5. **Confusing the secret name in AWS with the Kubernetes Secret name** -- The AWS Secrets Manager secret name (e.g., `my-app/secrets`) is different from the Kubernetes Secret name (e.g., `aws-secrets`). The `SecretProviderClass` maps between these two names.
6. **Base64 encoding errors** -- When creating Kubernetes Secrets via YAML, the `data` field values must be base64-encoded. Using `kubectl create secret --from-literal` handles this automatically, but manual YAML requires running `echo -n "value" | base64` (note the `-n` to avoid a trailing newline).
7. **Not restarting pods after creating the Secret** -- Pods stuck in `CreateContainerConfigError` will not automatically retry. You must delete the stuck pod or restart the deployment for a new pod to be scheduled that picks up the now-existing Secret.

## Additional Resources

- [AWS Secrets Manager CSI Driver](https://docs.aws.amazon.com/secretsmanager/latest/userguide/integrating_csi_driver.html)
- [Secrets Store CSI Driver](https://secrets-store-csi-driver.sigs.k8s.io/)
- [AWS Provider for Secrets Store CSI Driver](https://github.com/aws/secrets-store-csi-driver-provider-aws)
- [EKS IAM Roles for Service Accounts (IRSA)](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [Kubernetes Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)
- [Using Secrets as Environment Variables](https://kubernetes.io/docs/concepts/configuration/secret/#using-secrets-as-environment-variables)
