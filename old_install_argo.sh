#!/usr/bin/env bash

set -euxo pipefail

argo_cd_chart_version=8.1.4
argo_rollouts_chart_version=2.40.1
cert_manager_chart_version=1.18.2

kind create cluster --wait 120s --config k8s/kind-config.yaml
kind export kubeconfig --name microsvcs

helm install cert-manager cert-manager \
  --repo https://charts.jetstack.io \
  --version $cert_manager_chart_version \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true \
  --wait

helm install argocd argo-cd \
  --repo https://argoproj.github.io/argo-helm \
  --version $argo_cd_chart_version \
  --namespace argocd \
  --create-namespace \
  --set 'configs.secret.argocdServerAdminPassword=$2a$10$5vm8wXaSdbuff0m9l21JdevzXBzJFPCi8sy6OOnpZMAG.fOXL7jvO' \
  --set dex.enabled=false \
  --set notifications.enabled=false \
  --set server.service.type=NodePort \
  --set server.service.nodePortHttp=31443 \
  --set server.extensions.enabled=true \
  --set 'server.extensions.contents[0].name=argo-rollouts' \
  --set 'server.extensions.contents[0].url=https://github.com/argoproj-labs/rollout-extension/releases/download/v0.3.3/extension.tar' \
  --wait

helm install argo-rollouts argo-rollouts \
  --repo https://argoproj.github.io/argo-helm \
  --version $argo_rollouts_chart_version \
  --create-namespace \
  --namespace argo-rollouts \
  --wait

# Password is 'admin'
helm install kargo \
  oci://ghcr.io/akuity/kargo-charts/kargo \
  --namespace kargo \
  --create-namespace \
  --set api.service.type=NodePort \
  --set api.service.nodePort=31444 \
  --set api.adminAccount.passwordHash='$2a$10$Zrhhie4vLz5ygtVSaif6o.qN36jgs6vjtMBdM6yrU1FOeiAAMMxOm' \
  --set api.adminAccount.tokenSigningKey=iwishtowashmyirishwristwatch \
  --set externalWebhooksServer.service.type=NodePort \
  --set externalWebhooksServer.service.nodePort=31445 \
  --wait

# Apply the AppProject and ApplicationSet
kubectl apply -f argocd/project.yaml
kubectl apply -f argocd/applicationset.yaml

# Install ingress-nginx controller (if not already installed)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.14.1/deploy/static/provider/cloud/deploy.yaml
# helm upgrade --install ingress-nginx ingress-nginx \
#   --repo https://kubernetes.github.io/ingress-nginx \
#   --namespace ingress-nginx --create-namespace

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

# Check ingresses
kubectl get ingress -A | grep development
