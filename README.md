# dbt anywhere

[![Star this repo](https://img.shields.io/github/stars/sanlanka/dbt-anywhere?style=flat&logo=github&label=Star%20this%20repo&color=yellow)](https://github.com/sanlanka/dbt-anywhere)
[![Buy me a coffee](https://img.shields.io/badge/Buy%20me%20a%20coffee-FFDD00?logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/slanka10)

If this saved you a day of warehouse setup, a ⭐ helps others find it — and
[coffee](https://buymeacoffee.com/slanka10) keeps it maintained.

A working **dbt** project that runs on **Kubernetes** with one command — via
**Skaffold** and a small custom **Helm** chart — and connects to **the warehouse
you already have**: Snowflake, BigQuery, Redshift, Databricks, Postgres.

It deploys dbt, not a database. Your warehouse stays where it is, including on
your own machine.

## Quick start

```bash
cp .env.example .env    # point at your warehouse
./spinup.sh
```

The script installs any missing tooling (kubectl, helm, skaffold), turns your
`.env` into a Kubernetes Secret, builds the dbt image, deploys it, checks the
connection, runs `seed` → `run` → `test` against your warehouse, holds the
port-forward, and opens the UI when it's ready:

- dbt docs (DAG + catalog) → **http://localhost:8080** — opens automatically

`Ctrl-C` stops the port-forward; the pod keeps running. `./teardown.sh` removes
everything (`--namespace` deletes the `data` namespace too). Neither script ever
touches your warehouse.

**Prerequisites:** Docker Desktop with Kubernetes enabled (or minikube), and a
warehouse you can reach. On macOS the CLI tools install themselves via Homebrew.

Two things `spinup.sh` handles that otherwise bite you on a first run:

- **A missing database.** dbt creates schemas but never databases, so it prompts
  before creating one — Postgres and Redshift only, servers you own. `--yes`
  skips the prompt. Cloud warehouses are left alone.
- **A warehouse on this Mac.** Inside a pod, `localhost` is the pod. If `.env`
  points at `localhost`, the Secret gets `host.docker.internal` instead
  (`host.minikube.internal` on minikube) so the pod reaches your machine. Your
  `.env` is not modified.

**Where the repo lives matters.** The project is mounted into the pod, and
Docker Desktop only shares `/Users` and `/Volumes` by default — a clone in
`/tmp` leaves the pod stuck in `ContainerCreating`. Keep it under your home
directory, or add the path in Docker Desktop → Settings → Resources → File
Sharing. `spinup.sh` warns before deploying.

### If your local server refuses the connection

A Postgres bound to loopback only can't be reached from a pod no matter what
hostname it's given. `spinup.sh` detects this and says so before deploying. To
open it up, in `postgresql.conf`:

```
listen_addresses = '*'
```

and in `pg_hba.conf`, allow the Docker network:

```
host  all  all  192.168.65.0/24  scram-sha-256
```

then restart Postgres. (Postgres.app: Server Settings → Show config files.)

## What's in here

| Path              | What it is |
|-------------------|------------|
| `models/`         | The SQL. Each `.sql` file is one table or view dbt builds |
| `models/staging/` | One lightly-cleaned model per raw source. Materialized as views |
| `models/marts/`   | Business-facing models built from staging. Materialized as tables |
| `models/**/*.yml` | Descriptions and data tests for the models beside them |
| `seeds/`          | Small CSVs dbt loads into the warehouse — reference data, or demo data like here |
| `macros/`         | Reusable SQL snippets (Jinja functions). Empty until you need one |
| `tests/`          | Custom data tests that don't fit the built-in ones |
| `dbt_project.yml` | Project config: where things live, how each folder is materialized |
| `profiles.yml`    | Connection targets, all env-var driven. No secrets, safe to commit |
| `.env.example`    | Template for your warehouse credentials. Copy to `.env` (gitignored) |
| `spinup.sh`       | The entry point: deploy, run, serve the docs UI |
| `teardown.sh`     | Remove the deployment |
| `k8s/`            | The chart, image, and Skaffold config. See [k8s/README.md](k8s/README.md) |

Generated at runtime and gitignored: `target/` (compiled SQL and artifacts),
`logs/`, and `.env`.

## What it builds

```
seeds/raw_customers.csv  ─┐
seeds/raw_orders.csv     ─┴─► staging (views) ──► marts/customer_orders (table)
```

- **`stg_customers`, `stg_orders`** — light cleanup: type casts, a `full_name`
  column. Views, so they cost nothing to rebuild.
- **`customer_orders`** — one row per customer with completed-order counts,
  lifetime value, and first/most-recent order dates. A table, because it's what
  gets queried.

This shape — raw → staging → marts — is the convention dbt projects follow, and
it's worth keeping as you add your own models.

10 data tests cover uniqueness, not-null, referential integrity between orders
and customers, and the allowed set of order statuses. `dbt test` runs them.

## Connecting to your warehouse

Everything lives in `.env`, which is gitignored:

```bash
cp .env.example .env
```

```bash
# Snowflake, for example
DBT_TARGET=snowflake
DBT_SNOWFLAKE_ACCOUNT=ab12345.us-east-1
DBT_SNOWFLAKE_USER=dbt
DBT_SNOWFLAKE_PASSWORD=...
DBT_SNOWFLAKE_ROLE=TRANSFORMER
DBT_SNOWFLAKE_WAREHOUSE=COMPUTE_WH
DBT_SNOWFLAKE_DATABASE=ANALYTICS
DBT_SCHEMA=ANALYTICS
```

`profiles.yml` ships with targets for **postgres**, **redshift**, **snowflake**,
**bigquery**, **databricks**, and **duckdb**. `DBT_TARGET` picks one. Every
value has a default, so you only set what differs for you.

**Install the adapter for your warehouse.** The image ships with Postgres and
DuckDB only, to keep it small. Add yours in `k8s/skaffold.yaml`:

```yaml
        buildArgs:
          DBT_ADAPTERS: "dbt-postgres dbt-duckdb dbt-snowflake"
```

Then re-run `./spinup.sh` — Skaffold rebuilds the image.

### BigQuery

BigQuery also needs a service-account JSON file. Download it, then point at it:

```bash
DBT_TARGET=bigquery
DBT_BIGQUERY_PROJECT=my-gcp-project
DBT_BIGQUERY_KEYFILE=/secrets/bigquery.json
```

The JSON has to be a file inside the pod, so mount it as a Secret — see
[k8s/README.md](k8s/README.md).

## Everyday dbt commands

The project is mounted into the pod, so editing a model on your Mac and
re-running picks it up — no image rebuild:

```bash
kubectl exec -it -n data deploy/dbt-runner -- dbt run
kubectl exec -it -n data deploy/dbt-runner -- dbt run --select customer_orders
kubectl exec -it -n data deploy/dbt-runner -- dbt run --select stg_orders+
kubectl exec -it -n data deploy/dbt-runner -- dbt test
kubectl exec -it -n data deploy/dbt-runner -- dbt build   # seed + run + test

kubectl logs -f -l app=dbt-runner -n data                 # watch the pod
```

`--select` is the workhorse: model names, `+` for upstream/downstream, plus
`tag:` and `path:` selectors.

To refresh the docs site after an edit:

```bash
kubectl exec -n data deploy/dbt-runner -- dbt docs generate
kubectl rollout restart -n data deploy/dbt-runner
```

## Learning dbt

New to dbt? These are the ones worth your time, roughly in order:

- **[dbt Fundamentals](https://learn.getdbt.com/courses/dbt-fundamentals)** —
  free official course, a few hours, the fastest way in.
- **[Quickstart guides](https://docs.getdbt.com/guides)** — step-by-step for
  your specific warehouse.
- **[Building your first models](https://docs.getdbt.com/docs/build/models)** —
  what a model is and how materializations work.
- **[Tests](https://docs.getdbt.com/docs/build/data-tests)** and
  **[sources](https://docs.getdbt.com/docs/build/sources)** — the two things
  that make a project trustworthy.
- **[Jinja & macros](https://docs.getdbt.com/docs/build/jinja-macros)** — where
  dbt stops being "just SQL files".
- **[Best practices](https://docs.getdbt.com/best-practices)** — the staging /
  intermediate / marts structure this project follows, explained.
- **[dbt-utils](https://github.com/dbt-labs/dbt-utils)** — the package almost
  every project ends up installing.
- **[Node selection syntax](https://docs.getdbt.com/reference/node-selection/syntax)**
  — the full `--select` reference, worth a skim once you have a few models.
- **[dbt Slack](https://www.getdbt.com/community/join-the-community)** — an
  unusually helpful community if you get stuck.

## Adding your own models

1. Drop a `.sql` file in `models/staging/` that selects from a source, and one
   in `models/marts/` that joins them.
2. Reference other models with `{{ ref('other_model') }}` — that's how dbt knows
   the build order.
3. Describe it and add tests in the folder's `.yml` file.
4. `dbt build`.

When your data lives in the warehouse already (rather than in `seeds/`), declare
it with [sources](https://docs.getdbt.com/docs/build/sources) and use
`{{ source('name', 'table') }}` instead of `ref`.
