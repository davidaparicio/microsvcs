#!/usr/bin/env bash

set -euxo pipefail

# Install ArgoCD (if not already installed)
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD server to be ready
kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd
echo "ArgoCD installation and configuration complete."

# Print initial admin password
echo "Initial ArgoCD admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo

echo "You can access the ArgoCD UI by port-forwarding the argocd-server service:"
echo "kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "Then open your browser to https://localhost:8080"

# Note: Remember to change the admin password after first login for security purposes.

# Apply the AppProject and ApplicationSet
kubectl apply -f argocd/project.yaml
kubectl apply -f argocd/applicationset.yaml

# Wait for applications to be synced and healthy
echo "Waiting for applications to be synced and healthy..."
for app in red-app blue-app green-app yellow-app; do
  kubectl -n argocd wait --for=condition=Synced --timeout=600s app/$app
  kubectl -n argocd wait --for=condition=Healthy --timeout=600s app/$app
done
echo "All applications are synced and healthy." 

# Check namespaces created
kubectl get namespaces | grep -E "(red|blue|green|yellow)-development"

# Check pods
kubectl get pods -n red-development
kubectl get pods -n blue-development

# Check services
kubectl get svc -A | grep development