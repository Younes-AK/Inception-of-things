# Inception of Things

The root `Vagrantfile` provisions the VM used for Part 3. From the repository
root, start the Part 3 environment with:

```sh
vagrant up
```

The optional GitLab bonus uses the same VM and Vagrantfile. Select it with:

```sh
IOT_BONUS=1 vagrant up
```

Use the same `IOT_BONUS=1` prefix with `vagrant provision` when reprovisioning
the bonus environment. The mandatory Part 1 and Part 2 environments each keep
their own Vagrantfile under `p1/` and `p2/`.
