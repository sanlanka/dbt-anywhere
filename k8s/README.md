# Running this project on Kubernetes

Optional. The dbt project in the repo root runs fine on its own with `./run.sh`
— this folder is for running it *inside a cluster* instead, which is how you'd
schedule it next to the rest of your infrastructure.

It deploys **dbt only**. There is no database here: the pod connects out to the
warehouse configured in `.env` at the repo root.

```bash
cp .env.example .env    # in the repo root
k8s/spinup.sh
```

The script installs any missing tooling, turns `.env` into a Kubernetes Secret,
builds the dbt image, deploys it, checks the connection, runs `seed` → `run` →
`test`, holds the port-forward, and opens the docs UI at
**http://localhost:8080**.

Remove it with `k8s/teardown.sh` (add `--namespace` to delete the `data`
namespace too). Neither script ever touches your warehouse.

## What's in here

| Path                       | What it is |
|----------------------------|------------|
| `spinup.sh`                | The entry point: preflight checks, Secret, deploy, port-forward |
| `teardown.sh`              | Deletes the release and the credentials Secret |
| `skaffold.yaml`            | Ties it together — builds the image, deploys the chart, forwards :8080 |
| `charts/dbt/`              | The Helm chart |
| `charts/dbt/values.yaml`   | Every knob: image, adapters, resources, mounts. Start here |
| `charts/dbt/templates/dbt.yaml` | The dbt Deployment + the `dbt-docs` Service |
| `charts/dbt/templates/_helpers.tpl` | Reusable snippets for the optional mounts |
| `docker/dbt/Dockerfile`    | The runner image: Python 3.12, dbt, and your adapters |
| `docker/dbt/entrypoint.sh` | What the pod does on boot: connect, build, test, serve docs |

## How it fits together

```
.env  ──kubectl create secret──►  Secret/dbt-warehouse
                                        │ envFrom
repo root ──hostPath mount──►  Pod/dbt-runner ──► your warehouse
                                        │
                                  Service/dbt-docs :8080 ──► localhost:8080
```

- **Credentials** go in as a Secret built from `.env`, pulled into the container
  with `envFrom`. They never enter the chart, `helm get values`, or git. Re-run
  `spinup.sh` after editing `.env` to push a change.
- **The project itself is mounted, not baked in.** Editing a model on your Mac
  and re-running `dbt run` in the pod picks it up — no image rebuild. This uses
  a `hostPath` mount, which works on Docker Desktop and minikube because they
  share `/Users`. On a remote cluster, bake the project into the image instead.
- **Build output goes to `/tmp` in the pod** (`DBT_TARGET_PATH`), not into the
  mounted repo, so the pod's uid doesn't leave root-owned files in your git tree.

## Adding your warehouse adapter

The image ships with Postgres and DuckDB only, to keep it small. Add yours in
`skaffold.yaml`:

```yaml
        buildArgs:
          DBT_ADAPTERS: "dbt-postgres dbt-duckdb dbt-snowflake"
```

## Common tasks

```bash
kubectl exec -it -n data deploy/dbt-runner -- dbt run     # rebuild after an edit
kubectl exec -it -n data deploy/dbt-runner -- dbt test
kubectl logs -f -l app=dbt-runner -n data                 # watch the pod
kubectl get pods -n data
```

**Pod stuck in CrashLoopBackOff?** It couldn't reach the warehouse. The logs
print the failing connection details — check `.env`, that the adapter is in
`DBT_ADAPTERS`, and that your warehouse allows connections from your network.
