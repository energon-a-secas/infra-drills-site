#!/bin/bash
# Triage 10: Same deployment, healthy in staging, CrashLoopBackOff in production.
#
# The Deployments are byte-for-byte identical across both namespaces. The only
# difference is the ConfigMap the container reads its config from:
#   staging/checkout-config    has key DATABASE_URL   (correct)
#   production/checkout-config  has key DATABASE_URI   (typo — wrong key)
#
# The container requires a non-empty DATABASE_URL and exits 1 when it is empty,
# so production crash-loops while staging runs. The bug is invisible unless you
# diff the two environments — the manifests really are "the same".

kubectl create namespace staging 2>/dev/null
kubectl create namespace production 2>/dev/null

# ── staging: correct ConfigMap key ───────────────────────────────
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: checkout-config
  namespace: staging
data:
  DATABASE_URL: "postgres://checkout:secret@db.staging.svc:5432/checkout"
  LOG_LEVEL: "info"
EOF

# ── production: typo'd ConfigMap key (DATABASE_URI, not DATABASE_URL) ──
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: checkout-config
  namespace: production
data:
  DATABASE_URI: "postgres://checkout:secret@db.production.svc:5432/checkout"
  LOG_LEVEL: "info"
EOF

# ── identical Deployment applied to BOTH namespaces ──────────────
for NS in staging production; do
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: checkout
  namespace: ${NS}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: checkout
  template:
    metadata:
      labels:
        app: checkout
    spec:
      containers:
      - name: checkout
        image: busybox:1.36
        command: ["sh", "-c"]
        args:
          - |
            if [ -z "\$DATABASE_URL" ]; then
              echo "FATAL: DATABASE_URL is empty — cannot connect to database"
              exit 1
            fi
            echo "checkout started, DB=\$DATABASE_URL"
            exec sleep 3600
        envFrom:
        - configMapRef:
            name: checkout-config
EOF
done

echo ""
echo "Waiting for staging to settle..."
kubectl rollout status deployment/checkout -n staging --timeout=60s 2>/dev/null

echo ""
echo "Lab initialized."
echo "  staging/checkout    → Running (works)"
echo "  production/checkout → CrashLoopBackOff (broken)"
echo ""
echo "Ticket says: 'same image, same YAML, nothing is different.'"
echo "Test that claim. Compare the two environments."
echo ""
echo "Hint: kubectl get configmap checkout-config -n staging -o yaml"
echo "      kubectl get configmap checkout-config -n production -o yaml"
