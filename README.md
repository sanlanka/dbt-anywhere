# dbt anywhere

[![Star this repo](https://img.shields.io/github/stars/sanlanka/dbt-anywhere?style=flat&logo=github&label=Star%20this%20repo&color=yellow)](https://github.com/sanlanka/dbt-anywhere)
[![Buy me a coffee](https://img.shields.io/badge/Buy%20me%20a%20coffee-FFDD00?logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/slanka10)

If this saved you a day of warehouse setup, a ⭐ helps others find it — and
[coffee](https://buymeacoffee.com/slanka10) keeps it maintained.

One dbt project, deployed to **Kubernetes** with one command — Postgres and a
dbt runner via **Skaffold** and a small custom **Helm** chart. The same models
also run straight on your laptop, because nothing in them is engine-specific.

## Quick start

```bash
./spinup.sh
```

That's it — one command brings up everything. The script installs any missing
tooling (kubectl, helm, skaffold), builds the dbt image, deploys Postgres and
the dbt runner, runs `seed` → `run` → `test` inside the cluster, holds the
port-forwards, and opens the UI in your browser when it's ready:

- dbt docs (DAG + catalog) → **http://localhost:8080** — opens automatically
- Postgres → **localhost:15432** (user `dbt` / password `dbt` / db `dbt_local`)

Port 15432, not 5432, so a Postgres already running on your Mac keeps its port.
Pass `--no-browser` if you'd rather it didn't open a tab.

Press `Ctrl-C` to stop the port-forwards (the cluster keeps running). To remove
everything: `./teardown.sh` (add `--namespace` to delete the `data` namespace).

**Prerequisites:** Docker Desktop with Kubernetes enabled (or minikube). On
macOS the script auto-installs the CLI tools via Homebrew.

## Running it without Kubernetes

Same script, same ending — built, tested, docs UI open — with no cluster:

```bash
./spinup.sh --local       # Postgres: an existing one, or docker compose
./spinup.sh --local --duckdb   # no database server at all, warehouse is a file
./teardown.sh --local     # clean up what --local created
```

In `--local` mode the script creates the virtualenv, role, database, and schema
if they don't exist. It never touches databases it didn't create.

## Swapping the engine

Targets live in `profiles.yml`. Postgres is the default; DuckDB ships as a
zero-infrastructure fallback where the entire warehouse is a single file:

```bash
./run.sh --target duckdb     # no server, no Docker, nothing to install
dbt run --target duckdb      # or per-command
export DBT_TARGET=duckdb     # or for the whole shell
```

To add Snowflake, BigQuery, Redshift, or anything else, install the adapter and
add an output block — the models, tests, and DAG carry over untouched:

```bash
.venv/bin/pip install dbt-snowflake
```

```yaml
# profiles.yml, under outputs:
    snowflake:
      type: snowflake
      account: "{{ env_var('SNOWFLAKE_ACCOUNT') }}"
      ...
```

Every Postgres setting is an env var with a local-friendly default, so pointing
at a different server needs no file edits:

| Variable            | Default     |
|---------------------|-------------|
| `DBT_TARGET`        | `postgres`  |
| `DBT_PG_HOST`       | `localhost` |
| `DBT_PG_PORT`       | `5432`      |
| `DBT_PG_USER`       | `dbt`       |
| `DBT_PG_PASSWORD`   | `dbt`       |
| `DBT_PG_DATABASE`   | `dbt_local` |
| `DBT_PG_SCHEMA`     | `analytics` |

## What it builds

```
seeds/raw_customers.csv  ─┐
seeds/raw_orders.csv     ─┴─► staging (views) ──► marts/customer_orders (table)
```

- **`stg_customers`, `stg_orders`** — light cleanup: casts, a `full_name`
  column. Views, so they cost nothing to rebuild.
- **`customer_orders`** — one row per customer with completed-order counts,
  lifetime value, and first/most-recent order dates. Materialized as a table.

10 data tests cover uniqueness, not-null, referential integrity between orders
and customers, and the allowed set of order statuses.

## Poke at the results

```bash
# in-cluster Postgres, while spinup.sh is holding the port-forward
PGPASSWORD=dbt psql -h 127.0.0.1 -p 15432 -U dbt -d dbt_local -c 'table analytics.customer_orders'

# local Postgres (run.sh)
PGPASSWORD=dbt psql -h localhost -U dbt -d dbt_local -c 'table analytics.customer_orders'

# duckdb
.venv/bin/python -c "import duckdb; print(duckdb.connect('warehouse.duckdb').sql('select * from analytics.customer_orders'))"
```

## Working on it

The project directory is mounted into the dbt pod, so editing a model on your
Mac needs a re-run, never an image rebuild:

```bash
kubectl exec -it -n data deploy/dbt-runner -- dbt run
kubectl exec -it -n data deploy/dbt-runner -- dbt test
kubectl logs -f -l app=dbt-runner -n data
```

Locally it's the usual dbt loop:

```bash
export DBT_PROFILES_DIR="$PWD"
source .venv/bin/activate

dbt run --select stg_orders+     # a model and everything downstream
dbt test --select customer_orders
dbt build                        # seed + run + test in DAG order
dbt docs generate && dbt docs serve
```

## Layout

| Path                  | What's in it                                       |
|-----------------------|----------------------------------------------------|
| `skaffold.yaml`       | Builds the dbt image, deploys the chart, forwards ports |
| `charts/dbt/`         | The Helm chart (Postgres + dbt runner). Tune `charts/dbt/values.yaml` |
| `docker/dbt/`         | The dbt runner image and its entrypoint            |
| `spinup.sh`           | The one entry point: brings everything up, k8s or `--local` |
| `teardown.sh`         | Remove it all (`--local` for a non-k8s build)      |
| `dbt_project.yml`     | Project config; staging → views, marts → tables    |
| `profiles.yml`        | Connection targets, all env-var driven             |
| `docker-compose.yml`  | Postgres 16, only if you don't have one already    |
| `seeds/`              | CSVs loaded into the warehouse by `dbt seed`       |
| `models/staging/`     | One cleaned-up model per raw source                |
| `models/marts/`       | Business-facing models built from staging          |

`warehouse.duckdb`, `target/`, `logs/`, and `.venv/` are gitignored — everything
tracked is source, and any clone rebuilds the warehouse from scratch.
