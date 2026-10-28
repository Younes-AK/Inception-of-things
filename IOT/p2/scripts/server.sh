#!/bin/sh

set -e

IP="192.168.56.110"

curl -sfL https://get.k3s.io | sh -s - server \
  --node-ip "$IP" \
  --write-kubeconfig-mode 644


echo "alias k=kubectl" >> /etc/profile.d/k.sh

kubectl apply -f /vagrant/confs/
sudo apt install net-tools