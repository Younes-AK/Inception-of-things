# Inception-of-Things — The DevOps Guide

This guide teaches the concepts behind the project from the ground up, then walks through the solution file by file. Read Part A first (concepts), then Part B (the solution), then use Part C to rehearse your defense.

---

# PART A — CONCEPTS

## A1. The big picture: why does this project exist?

Modern software is shipped as **containers** and run by an **orchestrator** (Kubernetes). Infrastructure is described as **code** (files in git), and a **GitOps** tool keeps the running system identical to what git says.

The project is a staircase:

| Part | You learn | Key idea |
|---|---|---|
| p1 | Vagrant + K3s multi-node | *Infrastructure as Code* for VMs; what a cluster (server + agent) is |
| p2 | Deployments, Services, Ingress | How traffic gets routed *into* a cluster by hostname |
| p3 | K3d, Docker, Argo CD | Clusters in containers; **GitOps / continuous delivery** |
| bonus | GitLab + Helm | Self-hosting the git side; package management with Helm |

---

## A2. Virtualization, VMs, and Vagrant

**Virtual machine (VM):** a software-emulated computer with its own kernel and OS, run by a *hypervisor* (VirtualBox, KVM, VMware). Strong isolation, heavy (GBs of RAM/disk, boots in tens of seconds).

**Provider:** the backend Vagrant uses to create VMs (VirtualBox, libvirt, VMware...). The subject lets you choose.

**Vagrant:** a CLI that builds *reproducible* VMs from a text file (`Vagrantfile`, which is Ruby). Instead of clicking through an installer, you write:

- `config.vm.box` — the base image ("box"), e.g. `bento/ubuntu-24.04`.
- `config.vm.define "name"` — declare one machine (you can have many).
- `config.vm.hostname` — the OS hostname.
- `config.vm.network "private_network", ip: "..."` — attach a **host-only network** NIC with a fixed IP. The host and the VMs can reach each other, and VMs can reach each other, but the outside world cannot. Vagrant also always creates a first NAT NIC (used for internet access and SSH port forwarding).
- `config.vm.provider "virtualbox"` — provider-specific tuning (CPU, RAM, name).
- `config.vm.provision "shell"` — run a script *inside* the VM on first boot (this is how K3s gets installed).
- `config.vm.synced_folder` — mount a host folder into the VM (`/vagrant` by default). We use it to hand the K3s join token from server to worker.

**Core commands:** `vagrant up` (create + provision), `vagrant ssh <name>`, `vagrant halt`, `vagrant provision` (re-run scripts), `vagrant destroy -f`, `vagrant status`.

**Passwordless SSH:** Vagrant boxes ship with the public half of a well-known "insecure" key; Vagrant generates a per-machine private key in `.vagrant/` and uses it. So `vagrant ssh` needs no password. This satisfies the subject's SSH requirement.

**"Modern practices" in a Vagrantfile** (the subject warns about this):
- `Vagrant.configure("2")` (the example's `(2)` still works but "2" is canonical).
- No deprecated/removed things: no `box_url` to a dead CentOS 8 image (CentOS 8 is EOL), no hard-coded network interface names (`eth1` no longer exists on modern distros → we detect the interface by IP).
- Data-driven loops (`MACHINES.each`) instead of copy-pasting two near-identical blocks.
- Pass values via `env:` to provisioning scripts; keep logic in `scripts/*.sh`, not giant inline strings.
- Minimal resources, linked clones for speed.

**Idempotency:** a good provisioning script can be re-run without breaking things. K3s's installer is idempotent, which is why `vagrant provision` is safe.

---

## A3. Containers and Docker

**Container:** a normal Linux process (or group) that the kernel *isolates* using:
- **namespaces** — what the process can *see* (own PID tree, network stack, mounts, hostname);
- **cgroups** — how much CPU/RAM it can *use*;
- a layered **filesystem** (image layers + a thin writable layer).

A container shares the host kernel → starts in milliseconds and weighs MBs. A VM virtualizes hardware and runs its own kernel → heavier but stronger isolation.

**Image:** immutable template (layers) a container starts from. **Registry:** server storing images (Docker Hub). **Tag:** a human label on an image version: `wil42/playground:v1` vs `:v2`. Without a tag you get `:latest`, which is a moving target — never use it for reproducible deployments. **Digest** (`@sha256:...`) is the immutable identifier.

**Dockerfile → image → container:** `docker build -t me/app:v1 .` → `docker push` → `docker run`.

**containerd:** the lower-level container runtime that Kubernetes (and K3s) actually uses; Docker itself uses containerd under the hood. K3s does *not* need Docker; **K3d does** (it runs K3s *inside* Docker containers).

---

## A4. Kubernetes (K8s) — the essentials

Kubernetes is a **declarative** system: you tell the API server the *desired state* ("3 copies of app2 running"), and **controllers** continuously work to make *actual state* match. This reconcile loop is *the* core idea; Argo CD applies the very same idea one level up (git = desired state).

### Architecture
- **Control plane** ("server"/"master"): 
  - `kube-apiserver` — the only front door; everything (kubectl, kubelet, controllers) talks to it over REST.
  - `etcd` — the key-value database storing all cluster state.
  - `kube-scheduler` — picks a node for each new Pod.
  - `kube-controller-manager` — runs the reconcile loops (Deployment, ReplicaSet, Node, ...).
- **Worker node** ("agent"): 
  - `kubelet` — talks to the API, starts containers via the runtime.
  - `kube-proxy` — implements Service networking rules.
  - container runtime (containerd).
- **CNI plugin** — pod networking (K3s uses **Flannel**).

### Core objects (learn these cold)
| Object | What it is |
|---|---|
| **Pod** | Smallest unit; 1+ containers sharing network/storage. Ephemeral; has its own IP that changes on restart. |
| **ReplicaSet** | Keeps N identical Pods alive. You rarely create it directly. |
| **Deployment** | Manages ReplicaSets: replicas count, **rolling updates**, rollback. Changing the image tag creates a new ReplicaSet and gradually swaps Pods. |
| **Service** | Stable virtual IP + DNS name in front of a *set* of Pods chosen by **label selector**. Load-balances across them. Types: `ClusterIP` (internal, default), `NodePort`, `LoadBalancer`. |
| **Ingress** | HTTP(S) routing rules (host/path → Service). Needs an **Ingress controller** to enforce them. |
| **Namespace** | Logical partition of a cluster (names, quotas, RBAC). `argocd`, `dev`, `gitlab`, `kube-system`... |
| **ConfigMap / Secret** | Config and sensitive data injected as env vars/files. |
| **Labels & selectors** | Key/value tags; Services, Deployments, etc. find their Pods by them. If a Service's selector doesn't match your Pod labels → *no endpoints* → nothing works (the #1 beginner bug). |
| **CRD** | Custom Resource Definition: extends the API with new kinds. Argo CD adds `Application`; Traefik adds `IngressRoute`. |

### Manifests
YAML files describing objects: `apiVersion`, `kind`, `metadata`, `spec`. `kubectl apply -f file.yaml` is *declarative* (create-or-update). `kubectl create` is imperative.

### kubectl cheat sheet
```bash
kubectl get nodes -o wide
kubectl get all -A                    # everything, all namespaces
kubectl get pods -n dev -w            # watch
kubectl describe pod <p>              # events: the best debugging view
kubectl logs <p> [-f]
kubectl exec -it <p> -- sh
kubectl apply -f x.yaml / delete -f x.yaml
kubectl rollout status deploy/x
kubectl port-forward svc/x 8080:80    # tunnel to a Service from your machine
kubectl config get-contexts / use-context
```
Context = (cluster + user + namespace) stored in `~/.kube/config` (or `KUBECONFIG`). K3s writes `/etc/rancher/k3s/k3s.yaml`; K3d merges its context (`k3d-<name>`) into `~/.kube/config`.

---

## A5. K3s

**K3s** is a CNCF-certified, *lightweight* Kubernetes distribution by Rancher/SUSE: one ~70 MB binary, uses SQLite (or etcd) instead of full etcd by default, and **bundles batteries**:
- containerd (runtime), Flannel (CNI), CoreDNS (cluster DNS),
- **Traefik** (Ingress controller), **ServiceLB/Klipper** (LoadBalancer implementation), local-path-provisioner (storage), metrics-server.

(That is exactly what you see in `kube-system` in the subject's screenshots, including the `helm-install-traefik` jobs — K3s installs Traefik through an embedded Helm controller.)

**Roles:**
- `k3s server` = control plane (and also runs workloads unless tainted).
- `k3s agent` = worker; joins with `K3S_URL=https://<server>:6443` and `K3S_TOKEN` (from `/var/lib/rancher/k3s/server/node-token`).

**Important flags we use:**
- `--node-ip` — which IP the node advertises. On Vagrant the first NIC is NAT (10.0.2.15, identical on every VM!) — without this, nodes would advertise an unusable address.
- `--flannel-iface` — which NIC carries pod-to-pod overlay traffic (the private network one).
- `--write-kubeconfig-mode 644` — lets non-root read the kubeconfig.
- `--bind-address/--advertise-address` — where the API listens/announces.

**Why "K3s" for p1/p2 and "K3d" for p3?** See next section.

---

## A6. K3s vs K3d (the question the subject says you must understand)

| | **K3s** | **K3d** |
|---|---|---|
| What | A Kubernetes **distribution** | A **wrapper/tool** that runs K3s **inside Docker containers** |
| Needs | A Linux host/VM (installs as systemd service) | Docker |
| A "node" is | a machine | a Docker container |
| Create a cluster | install script on each machine | `k3d cluster create` (seconds) |
| Throw away | uninstall / destroy VM | `k3d cluster delete` |
| Multi-node | multiple VMs (p1) | `--agents N` = N more containers on one host |

K3d = *K3s in Docker*. You get disposable multi-node clusters on one laptop, perfect for dev/CI. K3d adds a `serverlb` container (an nginx proxy) in front, which is how `-p 8888:80@loadbalancer` publishes a host port.

**The point of the exercise:** same Kubernetes API, different packaging — and in p3 you drop Vagrant entirely.

---

## A7. Networking & Ingress (the heart of p2)

**Cluster networking rules:** every Pod gets a routable IP; Pods talk without NAT; Services give stable names (`svc.namespace.svc.cluster.local`) via CoreDNS.

**Why Ingress?** Exposing each app with its own `NodePort`/LoadBalancer wastes ports/IPs. One **Ingress controller** (a reverse proxy running in the cluster) listens on 80/443 and routes by **HTTP `Host` header** and path to different Services.

```
Browser ──► 192.168.56.110:80 ──► Traefik ──┬─ Host: app1.com ─► Service app-one ─► 1 pod
                                            ├─ Host: app2.com ─► Service app-two ─► 3 pods (load-balanced)
                                            └─ anything else  ─► Service app-three (default)
```

**Key insight:** it is *the same IP*; only the `Host:` header differs. That is called **name-based virtual hosting**. You test without DNS using:
```bash
curl -H "Host: app1.com" http://192.168.56.110
```
or add `192.168.56.110 app1.com app2.com` to the host's `/etc/hosts` for a browser.

**Ingress vs Ingress controller:** the `Ingress` object is just *rules* (data). Traefik (K3s default) watches those objects and reconfigures itself. No controller → rules do nothing. `ingressClassName: traefik` selects which controller owns the rule.

**A rule with no `host`** matches every request → that is our catch-all that sends unknown hosts to app3. More specific (host) rules win over it.

**Replicas:** `replicas: 3` on app2's Deployment → 3 Pods; the Service spreads requests across them (visible in the `pod:` line of hello-kubernetes changing when you refresh).

---

## A8. Continuous Integration / Delivery and GitOps

- **CI (integration):** build + test on every commit.
- **CD (delivery/deployment):** automatically ship the result to an environment.
- **Push-based CD (classic):** the CI pipeline runs `kubectl apply` from outside. Needs cluster credentials in CI; no one guarantees the cluster still matches reality.
- **GitOps (pull-based CD):** git is the *single source of truth*. An agent **inside** the cluster *pulls* the repo and reconciles. Benefits: audit trail (git log), trivial rollback (`git revert`), no cluster credentials outside, **drift detection/self-healing**.

**Two repositories pattern:** one for *application code → image* (Docker Hub), one for *config/manifests* (GitHub). In this project the "app" is already built (`wil42/playground:v1/v2`); your GitHub repo only holds manifests. Releasing = edit the tag in git, push.

---

## A9. Argo CD

Argo CD is a Kubernetes controller implementing GitOps. Components (all in the `argocd` namespace):
- `argocd-server` — API + web UI.
- `argocd-repo-server` — clones git, renders manifests (plain YAML/Helm/Kustomize).
- `argocd-application-controller` — compares **desired** (git) vs **live** (cluster) and syncs.
- `argocd-redis`, `argocd-dex-server`, `applicationset-controller`, `notifications-controller`.

**The `Application` CRD** is the unit of work:
```yaml
source:      {repoURL, targetRevision, path}   # WHERE the desired state lives
destination: {server, namespace}               # WHERE to deploy it
syncPolicy.automated: {prune, selfHeal}        # HOW eagerly
```
- **Synced / OutOfSync:** live matches git or not.
- **Healthy / Progressing / Degraded:** are the resources actually working.
- **prune:** delete cluster resources no longer in git.
- **selfHeal:** if someone `kubectl edit`s the Deployment, Argo reverts it.
- Default polling is every ~3 minutes (webhooks make it instant). The subject's demo (v1 → v2) works by: you push → Argo detects new commit → diff shows image changed → applies → Deployment rolls Pods → `curl` returns `v2`.
- `https://kubernetes.default.svc` as destination means "the cluster I'm running in".
- Initial admin password is in secret `argocd-initial-admin-secret`.

**Why two namespaces?** `argocd` = the tool; `dev` = the thing it deploys. Separation of concerns/permissions.

---

## A10. Helm and GitLab (bonus)

**Helm** = package manager for Kubernetes. A **chart** is a templated bundle of manifests; `values.yaml` customizes it; a **release** is an installed instance. `helm repo add`, `helm install/upgrade`, `helm uninstall`. (Even K3s's Traefik is installed by an embedded Helm controller.)

**GitLab** = self-hosted git + CI + UI. Its official chart deploys many pieces: webservice (Rails/Puma), sidekiq (jobs), gitaly (git storage), gitlab-shell (SSH), PostgreSQL, Redis, optional registry/runner/Prometheus. It is **heavy** (≥ ~6 GB RAM), so we disable everything not needed and swap its bundled NGINX ingress for K3s's Traefik.

**Why it integrates with Argo:** Argo CD only needs a git URL. Inside the cluster, GitLab is reachable at the Service DNS name `gitlab-webservice-default.gitlab.svc.cluster.local:8181`, so Argo's repo-server clones from it directly, while *you* push from the host through the Ingress (`gitlab.local:8888`). A **public** project means no credentials to configure.

---

# PART B — THE SOLUTION, EXPLAINED

Replace `wil` with a real team login everywhere (`LOGIN` in the Vagrantfiles, repo name on GitHub).

## B1. Directory layout (matches the subject)
```
.
├── p1/      Vagrantfile  scripts/{server,worker}.sh   confs/
├── p2/      Vagrantfile  scripts/server.sh            confs/{app1,app2,app3,ingress}.yaml
├── p3/      scripts/{install,setup}.sh  confs/{application.yaml, repo-template/manifests/*}
└── bonus/   scripts/{install,setup}.sh  confs/{gitlab-values,application}.yaml
```

## B2. p1 — Two VMs, one cluster

**`Vagrantfile`** loops over a `MACHINES` array. Per machine: name = `<login>S` / `<login>SW`, fixed IPs `.110`/`.111` on a private network, 1 CPU / 1024 MB (the subject allows 512 or 1024; Ubuntu 24.04 + K3s is happier with 1024), then runs its own provisioning script. `vagrant up` boots them in order, so the server finishes first.

**`server.sh`** step by step:
1. Detect the interface that owns `192.168.56.110` (avoids hard-coding `eth1`/`enp0s8`).
2. `curl get.k3s.io | INSTALL_K3S_EXEC="server ..." sh -` → installs K3s as a systemd service in **controller mode**.
3. Wait until the API answers.
4. Copy the node token to `/vagrant/node-token` (shared folder) for the worker.
5. Ensure an official `kubectl` exists and set `KUBECONFIG` + alias `k`.

**`worker.sh`:** waits for the token, then installs K3s with `K3S_URL=https://192.168.56.110:6443` + token and `agent` mode → it registers with the server as a node.

**Verify:**
```bash
vagrant up
vagrant ssh wilS -c "kubectl get nodes -o wide"
#  wils   Ready  control-plane,master  192.168.56.110
#  wilsw  Ready  <none>               192.168.56.111
vagrant ssh wilSW -c "ip a show | grep 192.168.56.111"
```
Troubleshooting: worker not joining → check `sudo journalctl -u k3s-agent`, verify `curl -k https://192.168.56.110:6443` from the worker, make sure `INTERNAL-IP` is the 192.168.56.x one, not 10.0.2.15.

## B3. p2 — One VM, three apps, Ingress

**Vagrantfile:** a single VM `<login>S` at `.110`.

**`server.sh`:** installs K3s, waits for `Ready`, waits for the **Traefik** rollout (otherwise your Ingress is created before a controller exists), then `kubectl apply -f /vagrant/confs/` which applies *every* YAML in the folder.

**Manifests:** each app = a Deployment + a Service.
- Image `paulbouwer/hello-kubernetes` (the one in the subject's screenshots; it shows the message, pod name, node). It listens on **8080**; the Service maps port 80 → `targetPort: 8080`.
- `MESSAGE` env var gives "Hello from appN."
- **app2 has `replicas: 3`.**
- `ingress.yaml`: two host rules (`app1.com`, `app2.com`) and one host-less rule → app3 (default).

**Verify (and show the Ingress to evaluators — the subject insists):**
```bash
kubectl get all
kubectl get ingress           # <- the thing they will ask to see
kubectl describe ingress apps-ingress
curl -H "Host: app1.com" 192.168.56.110     # Hello from app1.
curl -H "Host: app2.com" 192.168.56.110     # Hello from app2. (run several times; pod name varies)
curl 192.168.56.110                          # Hello from app3. (default)
curl -H "Host: whatever.org" 192.168.56.110  # Hello from app3.
```

## B4. p3 — K3d + Argo CD

**`install.sh`** (run it live in the defense): installs Docker (official apt repo), kubectl, k3d, argocd CLI; adds your user to the `docker` group.

**`setup.sh`:**
1. `k3d cluster create iot --agents 1 -p "8888:80@loadbalancer"` — 1 server + 1 agent container + a load balancer container; host port 8888 → Traefik port 80.
2. Creates namespaces `argocd` and `dev`.
3. Installs Argo CD from the official manifest (`--server-side` because the CRDs are too big for client-side apply) and waits for readiness.
4. Applies `confs/application.yaml` — the GitOps link.
5. Prints the admin password and the port-forward command for the UI.

**Your GitHub repo** (public, name contains a team login, e.g. `iot-wil`): copy `p3/confs/repo-template/manifests/` to the repo root:
- `deployment.yaml` → `image: wil42/playground:v1`, containerPort **8888**
- `service.yaml`, `ingress.yaml` → makes `curl localhost:8888` reach the app through Traefik.

Then set `repoURL` in `confs/application.yaml` to that repo.

**Demo flow for the defense**
```bash
sudo ./scripts/install.sh && ./scripts/setup.sh
kubectl get ns                       # argocd, dev
kubectl get pods -n dev
curl http://localhost:8888/          # {"status":"ok","message":"v1"}

# in your cloned GitHub repo:
sed -i 's/playground:v1/playground:v2/' manifests/deployment.yaml
git commit -am "v2" && git push
# Argo UI shows OutOfSync -> Synced (or click Refresh/Sync)
kubectl get pods -n dev -w           # old pod terminates, new appears
curl http://localhost:8888/          # {"status":"ok","message":"v2"}
```

**Own app option:** write a tiny web server, `docker build`, `docker tag me/app:v1`/`:v2`, `docker push` to a *public* Docker Hub repo, make the two versions visibly different, and point the manifest at it.

## B5. Bonus — GitLab

`setup.sh` creates a K3d cluster, namespaces `argocd`, `dev`, **`gitlab`**, installs Argo CD, then installs the official GitLab chart with `gitlab-values.yaml`:
- plain HTTP, host `gitlab.local`, Traefik as ingress, cert-manager/NGINX/Prometheus/registry/runner/KAS/MinIO disabled, single replicas, small requests.

It then prints the manual steps (they need a browser): add `127.0.0.1 gitlab.local` to `/etc/hosts`, log in as `root` with the generated password, create a **public** project `iot-repo`, push the manifests, apply the bonus `application.yaml` (which points Argo CD at the in-cluster GitLab URL). From then on, the v1 → v2 demo works with **local** GitLab instead of GitHub.

Honest warning: give the VM **≥ 8 GB RAM / 4 CPUs**; first install takes 10–20 minutes. And the bonus is graded only if the mandatory part is flawless.

---

# PART C — DEFENSE PREP

**Questions evaluators typically ask, with short answers**
1. *What is Vagrant for?* Reproducible VM definition as code.
2. *K3s vs K8s?* K3s is a lightweight, single-binary, CNCF-conformant K8s with bundled Traefik/Flannel/CoreDNS/containerd.
3. *K3s vs K3d?* K3d runs K3s nodes as Docker containers.
4. *What's an Ingress? Show it.* Rules; Traefik enforces them; `kubectl get/describe ingress`.
5. *Why 3 replicas and how are they balanced?* Deployment `replicas`; Service load-balances across matching pod endpoints.
6. *Deployment vs Pod vs ReplicaSet?* Deployment → ReplicaSet → Pods.
7. *What is GitOps / what does Argo CD do?* Pulls git, diffs against the cluster, syncs; git is the truth.
8. *Why two namespaces?* Isolation: tool vs workload.
9. *Show me a version change.* Run the demo flow (B4) live.
10. *What does `selfHeal` do? `prune`?* Reverts drift; deletes removed resources.
11. *What is a tag? Why not `latest`?* Mutable pointer, non-reproducible.
12. *Why `--node-ip`?* Vagrant's NAT NIC has the same IP on every VM; the cluster must use the private NIC.

**Command quick-reference for the day**
```bash
vagrant up / ssh / halt / destroy -f
kubectl get nodes,pods,svc,ingress -A
kubectl describe <kind> <name>
kubectl logs -n <ns> <pod>
k3d cluster list / delete iot
kubectl -n argocd get applications
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

**Common failure → fix**
| Symptom | Likely cause |
|---|---|
| Worker `NotReady`/missing | wrong `--node-ip`/iface, token not shared, firewall |
| Ingress returns 404 | Host header wrong, or service name/port typo |
| `502/503` from Traefik | Service selector doesn't match pod labels |
| Argo app `Unknown`/`ComparisonError` | wrong `repoURL`/`path`, repo is private |
| `ImagePullBackOff` | typo in image/tag or no internet |
| Argo stays old version | wait ≤3 min or hit **Refresh**; check you pushed to the right branch |
| `docker: permission denied` | re-login after being added to `docker` group |
