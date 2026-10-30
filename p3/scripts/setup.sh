
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Create cluster if it doesn't exist.
if ! k3d cluster list -o json 2>/dev/null \
  | grep -q '"name":"yakazdao"'; then
  k3d cluster create yakazdao \
    -p "8889:30888@loadbalancer"
fi

# Write the kubeconfig where kubectl looks by default, so plain
# `kubectl get nodes` works on any later login.
mkdir -p ~/.kube
k3d kubeconfig get yakazdao > ~/.kube/config
chmod 600 ~/.kube/config

# Wait for the cluster.
kubectl wait --for=condition=Ready nodes \
  --all --timeout=180s

# Create namespaces.
kubectl create namespace argocd \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create namespace dev \
  --dry-run=client -o yaml | kubectl apply -f -

# Install Argo CD.
kubectl apply --server-side -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl rollout status deployment/argocd-server \
  -n argocd --timeout=600s

# Deploy the application when ready.
kubectl apply -f /vagrant/p3/confs/application.yaml
echo "======================= Setup Done =========================="
