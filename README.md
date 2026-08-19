# dbt anywhere

[![Star this repo](https://img.shields.io/github/stars/sanlanka/dbt-anywhere?style=flat&logo=github&label=Star%20this%20repo&color=yellow)](https://github.com/sanlanka/dbt-anywhere)
[![Buy me a coffee](https://img.shields.io/badge/Buy%20me%20a%20coffee-FFDD00?logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/slanka10)

[![Page views](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/sanlanka/dbt-anywhere/traffic-stats/stats/views.json&cacheSeconds=300)](https://github.com/sanlanka/dbt-anywhere/blob/traffic-stats/stats/SUMMARY.md)
[![Unique visitors](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/sanlanka/dbt-anywhere/traffic-stats/stats/visitors.json&cacheSeconds=300)](https://github.com/sanlanka/dbt-anywhere/blob/traffic-stats/stats/SUMMARY.md)
[![Clones](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/sanlanka/dbt-anywhere/traffic-stats/stats/clones.json&cacheSeconds=300)](https://github.com/sanlanka/dbt-anywhere/blob/traffic-stats/stats/SUMMARY.md)

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

Then it drops you into a shell inside the dbt pod, so you can just type:

```
dbt:/dbt# dbt build                          seed + run + test
dbt:/dbt# dbt run --select customer_orders   build one model
dbt:/dbt# dbt test                           run the data tests
```

`exit` leaves the shell; the pod keeps running. `./teardown.sh` removes
everything. Neither script ever touches your warehouse.

Flags: `--no-shell` skips the shell and holds the port-forward instead (for CI),
`--no-browser` skips opening the tab, `--yes` skips the create-database prompt.

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
| `k8s/cronjob.example.yaml` | A scheduled `dbt build`, for running it on a clock |

## Everyday commands

The project is mounted into the pod, so an edit on your Mac needs a re-run, not
a rebuild. From the shell `spinup.sh` leaves you in:

```bash
dbt build                        # seed + run + test
dbt run --select customer_orders # one model
dbt run --select stg_orders+     # that model and everything downstream
dbt docs generate                # refresh the docs UI
```

Closed the shell? Get back in — or run a single command without one:

```bash
kubectl exec -it -n data deploy/dbt-runner -- bash
kubectl exec -n data deploy/dbt-runner -- dbt build
kubectl logs -f -l app=dbt-runner -n data
```

## Running it on a schedule

`spinup.sh` gives you a sandbox: a long-lived pod that builds once and serves
docs. A job that has to run four times a day is a different shape — a
**CronJob**, not a Deployment. [k8s/cronjob.example.yaml](k8s/cronjob.example.yaml)
is a working one; set `image` and the schedule, then:

```bash
kubectl apply -f k8s/cronjob.example.yaml -n data
kubectl create job --from=cronjob/dbt-scheduled dbt-manual-1 -n data   # run it now
kubectl logs job/dbt-manual-1 -n data
```

### The commands, and which one to schedule

| | |
|---|---|
| `dbt deps` | Install packages from `packages.yml` |
| `dbt parse` | Does the project make sense? No warehouse needed |
| `dbt source freshness` | Is the upstream data new enough to bother running? |
| `dbt compile` | Render the SQL that *would* run, without running it |
| `dbt run` | Build the models |
| `dbt test` | Assert the results are correct |
| `dbt build` | **run + test interleaved, in dependency order — schedule this one** |

`dbt build` is the one to put on a schedule, and the reason is worth knowing: it
runs each model and then immediately runs *that model's* tests, and **skips
everything downstream of a failed test**. A bad `stg_orders` stops right there
instead of quietly poisoning `customer_orders`. Run them separately with
`dbt run && dbt test` and the whole warehouse is already rebuilt from bad data
by the time the first test fails.

`dbt compile` is not a dry run. It renders `{{ ref() }}` into real table names
and stops — it will not tell you "this changes 4,000 rows." dbt has no preview
of what a run does to your data. Every run just runs.

Two behaviours that decide how a scheduled job should be configured:

- **Idempotency depends on materialization.** A `table` model is dropped and
  recreated each run, so re-running is free and safe. An `incremental` model is
  *stateful* — it appends or merges rows since the last run, so running it twice
  is not the same as running it once. `dbt run --full-refresh` is the rebuild
  from scratch, and it's what you reach for when an incremental model drifts.
- **Nothing stops two runs from colliding.** dbt has no locking. Two concurrent
  runs will fight over the same table, and overlapping incremental runs can
  double-count. `concurrencyPolicy: Forbid` in the CronJob is the only thing
  preventing it. Don't drop it.

### What one scheduled run does

Every six hours, Kubernetes starts a fresh pod that:

1. Reads warehouse credentials from the `dbt-warehouse` Secret (`envFrom`)
2. Runs `dbt build` — seeds, then models in dependency order, testing as it goes
3. Exits 0 on success, non-zero on any failure, and the pod goes away

Nothing persists between runs except what landed in your warehouse. That's the
point: the run is stateless, the warehouse holds the state.

The example sets `backoffLimit: 0` deliberately — **a failed dbt run should not
be retried automatically**. Unlike a flaky network call, a dbt failure is
usually bad upstream data or a broken model, and a retry just fails again two
minutes later while burning warehouse credits and hiding the signal.
`activeDeadlineSeconds` kills a hung run so it can't block the next slot.

One detail that will catch you: the CronJob overrides the image's entrypoint
with `command: ["dbt"]`. The default entrypoint ends in `dbt docs serve`, which
never exits — a Job using it would run forever instead of finishing.

### The one thing that changes on a real cluster

Locally the project is `hostPath`-mounted from your Mac, which is why editing a
model and re-running works with no rebuild. **A remote cluster has no such
directory.** For anything beyond your laptop, bake the project into the image
and drop the volume:

```dockerfile
# k8s/docker/dbt/Dockerfile
COPY . /dbt
```

That's the better production posture anyway: the image becomes an immutable
artifact tied to a git SHA, so "which version of the models produced this table"
has an answer. Build it in CI, push it to a registry, point `image:` at the tag.

### When a CronJob stops being enough

A CronJob runs dbt on a clock and knows nothing else. Reach for
[Airflow](https://airflow.apache.org/), [Dagster](https://dagster.io/), or
[dbt Cloud](https://www.getdbt.com/product/dbt-cloud) when you need any of:

- **Dependencies on other work** — run dbt *after* the ingestion job lands, not
  at 06:00 and hope
- **Per-model retries and backfills** — rerun just the failed subtree, or
  reprocess a date range
- **Alerting and lineage** across more than dbt

`dbt build` is the same command underneath. The orchestrator decides *when* and
*what to do about failure*; nothing about the project changes.

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
