
#!/usr/bin/env bash
set -euo pipefail

# Vagrant uploads shell provisioners to /tmp; the project is mounted here.
cd /vagrant/bonus

# Create and seed the GitLab source before Argo CD tries to clone it.
bash scripts/bootstrap-gitlab.sh

# Create cluster if it doesn't exist.
if ! k3d cluster list --no-headers 2>/dev/null \
  | awk '{print $1}' | grep -qx yakazdao; then
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

# GitLab runs on the VM; this namespace is reserved for the bonus requirement.
kubectl create namespace gitlab \
  --dry-run=client -o yaml | kubectl apply -f -

# Install Argo CD.
kubectl apply --server-side -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl rollout status deployment/argocd-server \
  -n argocd --timeout=600s

# Deploy the application when ready.
kubectl apply -f /vagrant/bonus/confs/application.yaml
kubectl wait -n argocd application/wil-playground \
  --for=jsonpath='{.status.sync.status}'=Synced --timeout=600s
kubectl wait -n argocd application/wil-playground \
  --for=jsonpath='{.status.health.status}'=Healthy --timeout=600s
echo "======================= Setup Done =========================="

# Replace any previous Argo CD forward, including one bound only to localhost.
# pkill -f '^kubectl port-forward .*svc/argocd-server 9000:443$' || true
nohup kubectl port-forward --address 0.0.0.0 -n argocd svc/argocd-server 9000:443 > /tmp/argocd-port-forward.log 2>&1 < /dev/null &
