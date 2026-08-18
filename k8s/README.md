# The Kubernetes deployment

The pieces `./spinup.sh` uses. You don't need to touch anything here to run the
project — this is for when you want to change how it's deployed.

It deploys **dbt only**. There is no database here: the pod connects out to the
warehouse configured in `.env` at the repo root.

```bash
./spinup.sh      # from the repo root
./teardown.sh
```

## What's in here

| Path                       | What it is |
|----------------------------|------------|
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
                                        │                 (anywhere reachable,
                                        │                  including this Mac)
                                  Service/dbt-docs :8080 ──► localhost:8080
```

- **A warehouse on your Mac** is reached as `host.docker.internal`
  (`host.minikube.internal` on minikube): inside a pod, `localhost` is the pod.
  `spinup.sh` rewrites the host when it builds the Secret, leaving your `.env`
  alone. The server must listen on more than loopback for this to work —
  `spinup.sh` warns you when it doesn't.

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

Then re-run `./spinup.sh`; Skaffold rebuilds the image.

## BigQuery

BigQuery needs the service-account JSON as a file in the pod:

```bash
kubectl create secret generic dbt-bigquery-key -n data \
  --from-file=bigquery.json=/path/to/service-account.json
```

```yaml
# charts/dbt/values.yaml
warehouse:
  keyfileSecret: dbt-bigquery-key
```

Then set `DBT_BIGQUERY_KEYFILE=/secrets/bigquery.json` in `.env`.

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
