#!/usr/bin/env bash
set -euo pipefail

# ArgoCD + Kargo Installation Script
# Creates a Kind cluster and installs ArgoCD, Argo Rollouts, cert-manager, and Kargo
# Usage: ./install_argo.sh [--skip-cluster] [--skip-wait] [--help]

# Colors (if terminal supports it)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# Version configuration
ARGO_CD_CHART_VERSION=8.1.4
ARGO_ROLLOUTS_CHART_VERSION=2.40.1
CERT_MANAGER_CHART_VERSION=v1.18.2
KARGO_VERSION="latest"  # or specify version like v0.8.0
INGRESS_NGINX_VERSION=v1.14.1

# Configuration
CLUSTER_NAME="microsvcs"
KIND_CONFIG="k8s/kind-config.yaml"

# Parse command line arguments
SKIP_CLUSTER=false
SKIP_WAIT=false
CLEAN_INSTALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-cluster)
            SKIP_CLUSTER=true
            shift
            ;;
        --skip-wait)
            SKIP_WAIT=true
            shift
            ;;
        --clean)
            CLEAN_INSTALL=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --skip-cluster   Skip Kind cluster creation (use existing cluster)"
            echo "  --skip-wait      Skip waiting for applications to be healthy"
            echo "  --clean          Delete existing cluster before creating new one"
            echo "  -h, --help       Show this help message"
            echo ""
            echo "What this script installs:"
            echo "  - Kind cluster (microsvcs)"
            echo "  - cert-manager ${CERT_MANAGER_CHART_VERSION}"
            echo "  - ArgoCD ${ARGO_CD_CHART_VERSION}"
            echo "  - Argo Rollouts ${ARGO_ROLLOUTS_CHART_VERSION}"
            echo "  - Kargo ${KARGO_VERSION}"
            echo "  - Ingress NGINX ${INGRESS_NGINX_VERSION}"
            echo ""
            echo "Credentials:"
            echo "  ArgoCD:  admin / admin"
            echo "  Kargo:   admin / admin"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Check dependencies
check_dependency() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${RED}❌ Error: $1 is not installed.${NC}"
        echo "   Please install it: $2"
        exit 1
    fi
}

echo -e "${BLUE}🔧 ArgoCD + Kargo Installation${NC}"
echo "================================"
echo ""

echo "🔍 Checking dependencies..."
check_dependency "kind" "https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
check_dependency "kubectl" "https://kubernetes.io/docs/tasks/tools/"
check_dependency "helm" "https://helm.sh/docs/intro/install/"
echo -e "  ${GREEN}✅${NC} All dependencies installed"
echo ""

# Clean install if requested
if [ "$CLEAN_INSTALL" = true ]; then
    echo -e "${YELLOW}🧹 Cleaning existing cluster...${NC}"
    kind delete cluster --name "${CLUSTER_NAME}" 2>/dev/null || true
    echo -e "  ${GREEN}✅${NC} Cluster deleted"
    echo ""
fi

# Create Kind cluster
if [ "$SKIP_CLUSTER" = false ]; then
    echo -e "${BLUE}📦 Creating Kind cluster...${NC}"
    echo "  Cluster: ${CLUSTER_NAME}"
    echo "  Config: ${KIND_CONFIG}"

    if ! [ -f "${KIND_CONFIG}" ]; then
        echo -e "${RED}❌ Error: Kind config not found at ${KIND_CONFIG}${NC}"
        exit 1
    fi

    if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
        echo -e "  ${YELLOW}⚠️  Cluster already exists${NC}"
        echo "     Use --clean to delete and recreate"
    else
        kind create cluster --wait 120s --config "${KIND_CONFIG}" --name "${CLUSTER_NAME}"
        echo -e "  ${GREEN}✅${NC} Cluster created"
    fi

    kind export kubeconfig --name "${CLUSTER_NAME}"
    echo -e "  ${GREEN}✅${NC} Kubeconfig exported"
    echo ""
else
    echo -e "${YELLOW}⏭️  Skipping cluster creation${NC}"
    echo ""
fi

# Install cert-manager
echo -e "${BLUE}📜 Installing cert-manager ${CERT_MANAGER_CHART_VERSION}...${NC}"
helm upgrade --install cert-manager cert-manager \
  --repo https://charts.jetstack.io \
  --version "${CERT_MANAGER_CHART_VERSION}" \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true \
  --wait
echo -e "  ${GREEN}✅${NC} cert-manager installed"
echo ""

# Install Ingress NGINX
echo -e "${BLUE}🌐 Installing Ingress NGINX ${INGRESS_NGINX_VERSION}...${NC}"
kubectl apply -f "https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-${INGRESS_NGINX_VERSION}/deploy/static/provider/cloud/deploy.yaml"
echo -e "  ${GREEN}✅${NC} Ingress NGINX installed"
echo ""

# Install ArgoCD
echo -e "${BLUE}🚀 Installing ArgoCD ${ARGO_CD_CHART_VERSION}...${NC}"
helm upgrade --install argocd argo-cd \
  --repo https://argoproj.github.io/argo-helm \
  --version "${ARGO_CD_CHART_VERSION}" \
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
echo -e "  ${GREEN}✅${NC} ArgoCD installed"
echo -e "  ${BLUE}🔗${NC} Access: http://localhost:31443 (admin/admin)"
echo ""

# Install Argo Rollouts
echo -e "${BLUE}🎲 Installing Argo Rollouts ${ARGO_ROLLOUTS_CHART_VERSION}...${NC}"
helm upgrade --install argo-rollouts argo-rollouts \
  --repo https://argoproj.github.io/argo-helm \
  --version "${ARGO_ROLLOUTS_CHART_VERSION}" \
  --create-namespace \
  --namespace argo-rollouts \
  --wait
echo -e "  ${GREEN}✅${NC} Argo Rollouts installed"
echo ""

# Install Kargo
echo -e "${BLUE}📦 Installing Kargo...${NC}"
helm upgrade --install kargo \
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
echo -e "  ${GREEN}✅${NC} Kargo installed"
echo -e "  ${BLUE}🔗${NC} Access: http://localhost:31444 (admin/admin)"
echo ""

# Apply ArgoCD resources
echo -e "${BLUE}📋 Applying ArgoCD resources...${NC}"
kubectl apply -f argocd/project.yaml
kubectl apply -f argocd/applicationset.yaml
echo -e "  ${GREEN}✅${NC} ArgoCD resources applied"
echo ""

# Apply Kargo secrets
echo -e "${BLUE}🔐 Applying Kargo secrets...${NC}"
if [ -f "kargo/.env" ]; then
    if bash kargo/apply-secrets.sh 2>/dev/null; then
        echo -e "  ${GREEN}✅${NC} Kargo secrets applied"
    else
        echo -e "  ${YELLOW}⚠️  Failed to apply secrets${NC}"
        echo "     You can apply them manually later with:"
        echo -e "     ${YELLOW}cd kargo && ./apply-secrets.sh${NC}"
    fi
else
    echo -e "  ${YELLOW}⚠️  No .env file found${NC}"
    echo "     Secrets not configured. To set up Kargo credentials:"
    echo "     1. cd kargo"
    echo "     2. cp .env.example .env"
    echo "     3. Edit .env with your GitHub and DockerHub credentials"
    echo "     4. ./apply-secrets.sh"
fi
echo ""

# Generate and apply Kargo configuration
echo -e "${BLUE}📦 Generating and applying Kargo configuration...${NC}"
if [ -f "kargo/generate.sh" ]; then
    # Generate Kargo manifests
    echo "  Generating Kargo manifests..."
    if (cd kargo && bash generate.sh --no-backup > /dev/null 2>&1); then
        echo -e "  ${GREEN}✅${NC} Kargo manifests generated"

        # Apply Kargo resources
        echo "  Applying Kargo resources..."
        kubectl apply -f kargo/generated/project.yaml 2>/dev/null || true
        kubectl apply -f kargo/generated/warehouses/ 2>/dev/null || true
        kubectl apply -f kargo/generated/stages/ 2>/dev/null || true
        echo -e "  ${GREEN}✅${NC} Kargo configuration applied"
    else
        echo -e "  ${YELLOW}⚠️  Failed to generate Kargo manifests${NC}"
        echo "     You can generate and apply them manually later with:"
        echo -e "     ${YELLOW}cd kargo && ./generate.sh --apply${NC}"
    fi
else
    echo -e "  ${YELLOW}⚠️  kargo/generate.sh not found${NC}"
fi
echo ""

# Wait for applications
if [ "$SKIP_WAIT" = false ]; then
    echo -e "${YELLOW}⏳ Waiting for applications to be synced and healthy...${NC}"
    echo "   This may take several minutes..."

    SERVICES=(red blue green yellow)
    ENVIRONMENTS=(development staging production)

    for service in "${SERVICES[@]}"; do
        for env in "${ENVIRONMENTS[@]}"; do
            app="${service}-${env}"
            echo -n "   • ${app}: "
            if kubectl -n argocd wait --for=condition=Synced --timeout=600s "app/${app}" &> /dev/null; then
                if kubectl -n argocd wait --for=condition=Healthy --timeout=600s "app/${app}" &> /dev/null; then
                    echo -e "${GREEN}✅ synced & healthy${NC}"
                else
                    echo -e "${YELLOW}⚠️  synced but not healthy${NC}"
                fi
            else
                echo -e "${RED}❌ failed to sync${NC}"
            fi
        done
    done
    echo ""
else
    echo -e "${YELLOW}⏭️  Skipping wait for applications${NC}"
    echo ""
fi

# Verification
echo -e "${GREEN}✨ Installation complete!${NC}"
echo ""
echo "📊 Verification:"
echo ""

echo "📦 Namespaces:"
kubectl get namespaces | grep -E "(red|blue|green|yellow)-development" || echo "  No development namespaces found yet"
echo ""

echo "🏃 Pods in red-development:"
kubectl get pods -n red-development 2>/dev/null || echo "  Namespace not ready yet"
echo ""

echo "🏃 Pods in blue-development:"
kubectl get pods -n blue-development 2>/dev/null || echo "  Namespace not ready yet"
echo ""

echo "🌐 Services:"
kubectl get svc -A | grep development || echo "  No services found yet"
echo ""

echo "🔗 Ingresses:"
kubectl get ingress -A | grep development || echo "  No ingresses found yet"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${GREEN}🎉 Setup Complete!${NC}"
echo ""
echo "Access Points:"
echo -e "  ${BLUE}ArgoCD:${NC}  http://localhost:31443 (admin/admin)"
echo -e "  ${BLUE}Kargo:${NC}   http://localhost:31444 (admin/admin)"
echo ""
echo "Next Steps:"
echo "  1. Access ArgoCD to verify applications are synced"
echo "  2. Configure Kargo secrets (if not already done):"
echo -e "     ${YELLOW}cd kargo && cp .env.example .env${NC}"
echo "     Edit .env with your credentials, then:"
echo -e "     ${YELLOW}./apply-secrets.sh${NC}"
echo "  3. Generate Kargo manifests:"
echo -e "     ${YELLOW}./generate.sh${NC}"
echo "  4. Apply Kargo configuration:"
echo -e "     ${YELLOW}kubectl apply -f generated/${NC}"
echo "  5. Access Kargo to view promotion stages"
echo ""
echo "Useful Commands:"
echo "  • Check cluster: kubectl cluster-info --context kind-${CLUSTER_NAME}"
echo "  • List apps: kubectl get apps -n argocd"
echo "  • View logs: kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server"
echo "  • Delete cluster: kind delete cluster --name ${CLUSTER_NAME}"
echo ""
