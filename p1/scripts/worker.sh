
#!/bin/bash
set -e

SERVER=192.168.56.110
IP="192.168.56.111"

echo "Waiting for K3s token..."
until [ -s /vagrant/node-token ]; do
  sleep 3
done

echo "Waiting for K3s API..."
until timeout 2 bash -c "</dev/tcp/$SERVER/6443" 2>/dev/null; do
  sleep 3
done

TOKEN=$(cat /vagrant/node-token)

echo "Joining K3s cluster..."

curl -sfL https://get.k3s.io | \
  K3S_URL=https://$SERVER:6443 \
  K3S_TOKEN="$TOKEN" \
  INSTALL_K3S_EXEC="agent --node-ip="$IP" --flannel-iface=enp0s8" \
  sh -

echo "alias k=kubectl" >> /etc/profile.d/k.sh
echo "Worker joined the K3s cluster."
sudo apt install net-tools