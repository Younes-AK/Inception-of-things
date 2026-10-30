#!/bin/sh

set -e

IP="192.168.56.110"

curl -sfL https://get.k3s.io | sh -s - server \
  --node-ip "$IP" \
  --write-kubeconfig-mode 644

cp /var/lib/rancher/k3s/server/node-token /vagrant/node-token

echo "alias k=kubectl" >> /etc/profile.d/k.sh

sudo apt install net-tools