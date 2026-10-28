

#!/usr/bin/env bash
set -euo pipefail



if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
fi

usermod -aG docker vagrant


if ! command -v kubectl >/dev/null 2>&1; then
  KUBECTL_VERSION="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
  curl -fsSLo /tmp/kubectl \
    "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
  install -m 0755 /tmp/kubectl /usr/local/bin/kubectl
  rm -f /tmp/kubectl
fi


if ! command -v k3d >/dev/null 2>&1; then
  curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh \
    | bash
fi

# GitLab CE prerequisites
apt-get update
apt-get install -y curl ca-certificates tzdata perl

# Add the official GitLab CE repository
curl -fsSL \
  https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh \
  | bash

# Install GitLab
EXTERNAL_URL="http://192.168.56.10" \
  apt-get install -y gitlab-ce

# Keep the public URL correct when provisioning an already-installed package.
if grep -q '^external_url ' /etc/gitlab/gitlab.rb; then
  sed -i "s|^external_url .*|external_url 'http://192.168.56.10'|" \
    /etc/gitlab/gitlab.rb
else
  echo "external_url 'http://192.168.56.10'" >> /etc/gitlab/gitlab.rb
fi
gitlab-ctl reconfigure

echo "Docker, kubectl, k3d and GitLab CE installed."
echo "The vagrant user was added to the docker group."
echo "GitLab initial root password: /etc/gitlab/initial_root_password"
