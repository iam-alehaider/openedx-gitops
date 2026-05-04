#!/usr/bin/env bash
# Run ONCE after EKS cluster exists.
# Installs ArgoCD and applies the root App of Apps.
# After this, ArgoCD manages everything else from Git.
set -euo pipefail

CLUSTER_NAME="${1:?Usage: $0 <cluster-name> [region]}"
AWS_REGION="${2:-us-east-1}"
ARGOCD_VERSION="v2.10.2"

echo "▶ Connecting kubectl to $CLUSTER_NAME..."
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"
kubectl cluster-info

echo "▶ Creating argocd namespace..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

echo "▶ Installing ArgoCD $ARGOCD_VERSION..."
kubectl apply -n argocd \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

echo "▶ Waiting for ArgoCD server to be ready..."
kubectl wait --for=condition=available --timeout=300s \
  deployment/argocd-server -n argocd

echo "▶ Patching ArgoCD server to insecure mode (TLS terminated at ALB)..."
kubectl patch deployment argocd-server -n argocd \
  --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--insecure"}]'

echo "▶ Getting ArgoCD initial admin password..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)
echo ""
echo "  ArgoCD admin password: $ARGOCD_PASSWORD"
echo "  ⚠️  SAVE THIS PASSWORD — change it immediately after login"
echo ""

echo "▶ Applying root App of Apps..."
kubectl apply -f apps/bootstrap/root-app.yaml

echo ""
echo "✅ ArgoCD bootstrap complete!"
echo ""
echo "  Access ArgoCD UI:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  Open: https://localhost:8080"
echo "  User: admin"
echo "  Pass: $ARGOCD_PASSWORD"
echo ""
echo "  ArgoCD will now sync all applications from:"
echo "  https://github.com/iam-alehaider/openedx-gitops"
