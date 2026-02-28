#!/usr/bin/env bash
set -euo pipefail

# Lab initialization for eks-29-secrets-manager
# Prerequisites: minikube running (make start from kubernetes/)

kubectl apply -f deployment.yaml
