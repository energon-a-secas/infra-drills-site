# Kubernetes

## Naming Convention

- **`k8s-`** prefix: Generic Kubernetes drills that work on any cluster (minikube, kind, etc.)
- **`eks-`** prefix: AWS EKS-specific drills (ALB ingress, IRSA, Secrets Manager CSI, etc.)

## Limitations

- EKS-specific drills (`eks-` prefix) require additional AWS tooling and may not fully replicate in minikube
- NetworkPolicy drills require a CNI that supports network policies (e.g., Calico). Enable with: `minikube start --cni=calico`

## Setup

```bash
make install   # Install kubectl, kubectx, minikube
make start     # Start minikube
```

## Usage

Each drill folder contains a `README.md` with the problem description and a `template.yaml` (or multiple YAML files) to deploy.

```bash
# Initialize a drill
cd <drill-folder>
bash lab-initialization.sh

# Or apply directly
kubectl apply -f template.yaml
```
