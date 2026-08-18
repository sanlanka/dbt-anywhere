# dbt anywhere

[![Star this repo](https://img.shields.io/github/stars/sanlanka/dbt-anywhere?style=flat&logo=github&label=Star%20this%20repo&color=yellow)](https://github.com/sanlanka/dbt-anywhere)
[![Buy me a coffee](https://img.shields.io/badge/Buy%20me%20a%20coffee-FFDD00?logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/slanka10)

A working **dbt** project that runs on **Kubernetes** with one command and
connects to **the warehouse you already have** — Snowflake, BigQuery, Redshift,
Databricks, Postgres, or a Postgres on your own laptop.

It deploys dbt, not a database.

**New to dbt?** [EXAMPLE.md](EXAMPLE.md) walks through what dbt is, what this
project builds, and how to verify every piece of it in Postgres.

If this saved you a day of setup, a ⭐ helps others find it — and
[coffee](https://buymeacoffee.com/slanka10) keeps it maintained.

## Quick start

```bash
cp .env.example .env    # point it at your warehouse
./spinup.sh
```

`spinup.sh` installs any missing tooling (kubectl, helm, skaffold), turns `.env`
into a Kubernetes Secret, builds the image, deploys it, runs `seed` → `run` →
`test` against your warehouse, and opens the docs UI at
**http://localhost:8080**.

`Ctrl-C` stops the port-forward; the pod keeps running. `./teardown.sh` removes
everything. Neither script ever touches your warehouse.

**Prerequisites:** Docker Desktop with Kubernetes enabled (or minikube). Keep
the repo under your home directory — Docker Desktop only shares `/Users` by
default, and the project is mounted into the pod.

Copy `.env.example` and change nothing and it still runs, against a local DuckDB
file. Point it somewhere real when you're ready.

## Connecting your warehouse

Everything is in `.env` (gitignored). `DBT_TARGET` picks one of the targets in
`profiles.yml`: `postgres`, `redshift`, `snowflake`, `bigquery`, `databricks`,
`duckdb`. Every value has a default, so set only what differs.

```bash
# Postgres already running on your Mac — works as-is, no changes to Postgres
DBT_TARGET=postgres
DBT_PG_HOST=localhost
DBT_PG_USER=your_username     # `whoami` on a Homebrew / Postgres.app install
DBT_PG_PASSWORD=
DBT_PG_DATABASE=analytics
DBT_SCHEMA=analytics
```

Two things `spinup.sh` handles for you:

- **`localhost` means the pod, not your Mac** — the Secret gets
  `host.docker.internal` instead (`host.minikube.internal` on minikube). Works
  even when Postgres listens on loopback only, since Docker Desktop connects
  from the host side. Your `.env` is left as written.
- **A missing database** — dbt creates schemas but never databases, so it offers
  to create one. Postgres and Redshift only; `--yes` skips the prompt.

**Add your adapter.** The image ships with Postgres and DuckDB. For others, edit
`DBT_ADAPTERS` in `k8s/skaffold.yaml` and re-run `./spinup.sh`. BigQuery also
needs its service-account JSON mounted as a Secret — see
[k8s/README.md](k8s/README.md).

## What it builds

```
seeds/*.csv ──► models/staging/ (views) ──► models/marts/customer_orders (table)
```

Raw → staging → marts is the standard dbt layout; keep it as you add your own.
10 data tests cover uniqueness, not-null, referential integrity, and accepted
values. [EXAMPLE.md](EXAMPLE.md) walks through all of it against a real Postgres,
including making a test fail on purpose.

| Path              | What it is |
|-------------------|------------|
| `models/`         | The SQL — each file is one table or view, plus `.yml` docs and tests |
| `seeds/`          | CSVs dbt loads into the warehouse |
| `macros/`         | Reusable SQL snippets (Jinja). Empty until you need one |
| `tests/`          | Custom data tests beyond the built-ins |
| `dbt_project.yml` | Where things live and how each folder is materialized |
| `profiles.yml`    | Connection targets, env-var driven. No secrets, safe to commit |
| `.env.example`    | Template for your credentials → copy to `.env` |
| `spinup.sh` / `teardown.sh` | Deploy and remove |
| `k8s/`            | Chart, image, Skaffold config — [k8s/README.md](k8s/README.md) |

## Everyday commands

The project is mounted into the pod, so an edit needs a re-run, not a rebuild:

```bash
kubectl exec -it -n data deploy/dbt-runner -- dbt build          # seed+run+test
kubectl exec -it -n data deploy/dbt-runner -- dbt run --select customer_orders
kubectl exec -it -n data deploy/dbt-runner -- dbt run --select stg_orders+
kubectl logs -f -l app=dbt-runner -n data
```

## Adding your own models

Write a `.sql` file in `models/`, reference others with `{{ ref('model_name') }}`
so dbt knows the build order, describe it in the folder's `.yml`, then
`dbt build`. For data already in your warehouse, declare
[sources](https://docs.getdbt.com/docs/build/sources) and use `{{ source() }}`
instead of `ref`.

## Learning dbt

- [dbt Fundamentals](https://learn.getdbt.com/courses/dbt-fundamentals) — free
  official course, a few hours, the fastest way in
- [Models](https://docs.getdbt.com/docs/build/models) ·
  [Tests](https://docs.getdbt.com/docs/build/data-tests) ·
  [Sources](https://docs.getdbt.com/docs/build/sources) ·
  [Jinja & macros](https://docs.getdbt.com/docs/build/jinja-macros)
- [Best practices](https://docs.getdbt.com/best-practices) — the staging/marts
  structure this project follows
- [Node selection](https://docs.getdbt.com/reference/node-selection/syntax) —
  the full `--select` reference
- [dbt-utils](https://github.com/dbt-labs/dbt-utils) ·
  [dbt Slack](https://www.getdbt.com/community/join-the-community)
