#!/usr/bin/env bash
set -euo pipefail

# Lab initialization for eks-01-broken-deploy
# Prerequisites: minikube running (make start from kubernetes/)

kubectl apply -f deployment.yaml
