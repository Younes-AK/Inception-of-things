# Bonus: GitLab with K3d and Argo CD

This bonus installs the latest official GitLab CE package on the Vagrant VM and
runs Argo CD plus the playground application in K3d. It creates the required
`gitlab` namespace. From the host, open GitLab at `http://localhost:8081`; the
VM and K3d use `http://192.168.56.10` to reach GitLab directly.

## Start

From the repository root, run:

```sh
IOT_BONUS=1 vagrant up
```

Provisioning waits for GitLab, creates the public **`root/app`** project,
commits `confs/manifests` to `main`, and creates the Argo CD Application.
It finishes once the Application is `Synced` and `Healthy`. No manual project
creation, first push, password, or access-token configuration is needed.

`bonus/scripts/bootstrap-gitlab.sh` reads the repository URL, branch, and destination
path from `bonus/confs/application.yaml` and seeds the checked-in
`bonus/confs/manifests/deployment.yaml`. The defaults work with the included Vagrant
VM. Keep the repository under the `root` account.

The Bash script uses `sudo gitlab-rails runner` on the VM to create the project
and initial commit directly. No password or API token is needed. The public
project lets Argo CD clone over HTTP without credentials in the cluster.

To rerun setup on an existing VM:

```sh
IOT_BONUS=1 vagrant provision
```

An existing repository with commits is preserved; bootstrap checks that the
deployment file exists on the configured branch. An existing private project
causes a clear error; make it public before rerunning. Future deployment changes must be committed to
the GitLab repository. Editing the local seed file and provisioning again
does not replace existing repository contents.

To sign in to GitLab as `root`, read the initial password from the host with:

```sh
vagrant ssh -c 'sudo cat /etc/gitlab/initial_root_password'
```

GitLab removes this password file after its initial setup period; save the
password or change it after your first sign-in.

For subsequent edits, clone the seeded repository from the host. Use the
forwarded host URL rather than GitLab's advertised VM URL:

```sh
git clone http://localhost:8081/root/app.git
cd app
# Edit bonus/confs/manifests/deployment.yaml, then:
git add bonus/confs/manifests/deployment.yaml
git commit -m "Update playground image"
git push origin main
```

Argo CD reads `confs/manifests` from the `main` branch of this project and
deploys it to the `dev` namespace. The Application uses automated sync with
pruning and self-healing, so pushed Git changes are applied automatically.

Run `kubectl` commands inside the VM (`vagrant ssh`). To demonstrate the workflow:

1. Confirm Argo CD sees the repository and the `wil-playground` application is
   synced: `kubectl -n argocd get application wil-playground`.
2. Confirm the required namespace and deployed app: `kubectl get namespaces`
   and `kubectl -n dev get deployment,service`.
3. Open `http://localhost:8889/` from the host and confirm the playground
   responds.
4. Change the image in `bonus/confs/manifests/deployment.yaml`, commit, and push to
   `main`. Wait for Argo CD to report `Synced`, then confirm the deployment
   reflects the pushed change and the app still responds.

Setup starts Argo CD forwarding in the background. Open
`https://localhost:9000` from the host. The playground is already forwarded
at `http://localhost:8889`. Forwarding ends when the VM or target pod stops;
rerun the forwarding command inside the VM if needed:

```sh
nohup kubectl port-forward --address 0.0.0.0 -n argocd svc/argocd-server 9000:443 > /tmp/argocd-port-forward.log 2>&1 < /dev/null &
```
