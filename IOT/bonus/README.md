# Bonus: GitLab with K3d and Argo CD

This bonus installs the latest official GitLab CE package on the Vagrant VM and
runs Argo CD plus the playground application in K3d. It creates the required
`gitlab` namespace. From the host, open GitLab at `http://localhost:8081`; the
VM and K3d use `http://192.168.56.10` to reach GitLab directly.

## Start

From `IOT/bonus`, run:

```sh
vagrant up
```

GitLab can take a few minutes to finish its first startup. Sign in as `root`;
read the initial password on the VM with:

```sh
sudo cat /etc/gitlab/initial_root_password
```

Create a **public, blank project** named `argocd` under the `root` account. A
public project lets Argo CD clone over HTTP without storing credentials in the
cluster. The bonus repository already has that project's local Git remote
configured. From `IOT/bonus`, push its manifests:

```sh
git push -u origin HEAD:main
```

Argo CD reads `confs/manifests` from the `main` branch of this project and
deploys it to the `dev` namespace. The Application uses automated sync with
pruning and self-healing, so pushed Git changes are applied automatically.

To demonstrate the complete workflow:

1. Confirm Argo CD sees the repository and the `wil-playground` application is
   synced: `kubectl -n argocd get application wil-playground`.
2. Confirm the required namespace and deployed app: `kubectl get namespaces`
   and `kubectl -n dev get deployment,service`.
3. Open `http://localhost:8889/` from the host and confirm the playground
   responds.
4. Change the image in `confs/manifests/deployment.yaml`, commit, and push to
   `main`. Wait for Argo CD to report `Synced`, then confirm the deployment
   reflects the pushed change and the app still responds.
