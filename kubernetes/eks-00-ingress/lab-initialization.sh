#!/usr/bin/env bash
set -euo pipefail

# Lab initialization for eks-00-ingress
# Prerequisites: minikube running (make start from kubernetes/)

minikube addons enable ingress

kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f ingress.yaml
