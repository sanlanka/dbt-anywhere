# dbt anywhere

[![Star this repo](https://img.shields.io/github/stars/sanlanka/dbt-anywhere?style=flat&logo=github&label=Star%20this%20repo&color=yellow)](https://github.com/sanlanka/dbt-anywhere)
[![Buy me a coffee](https://img.shields.io/badge/Buy%20me%20a%20coffee-FFDD00?logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/slanka10)

If this saved you a day of warehouse setup, a ⭐ helps others find it — and
[coffee](https://buymeacoffee.com/slanka10) keeps it maintained.

A working **dbt** project that connects to **the warehouse you already have** —
Snowflake, BigQuery, Redshift, Databricks, Postgres — or to a zero-setup local
sandbox if you just want to see it run. One command builds it, tests it, and
opens the docs UI.

It runs dbt. It never spins up a database for you.

## Quick start

No warehouse, no config, nothing to install but Python:

```bash
./run.sh --duckdb
```

That builds the project against a local file and opens the DAG at
**http://localhost:8080**. Point it at something real when you're ready:

```bash
cp .env.example .env    # edit: warehouse type, host, credentials
./run.sh
```

`run.sh` creates the virtualenv on first use, checks the connection, runs
`seed` → `run` → `test`, generates the docs, and serves them. `Ctrl-C` stops it;
`./run.sh --clean` removes the virtualenv and build output.

**If the database doesn't exist yet**, `run.sh` offers to create it — but only
for Postgres and Redshift, servers you own:

```
==> Database 'analytics' does not exist on localhost:5432. Create it? [y/N]
```

`--yes` skips the prompt (for scripts and CI). Snowflake, BigQuery, and
Databricks are never touched: creating databases there is rarely yours to do.
dbt itself always creates the *schema*, on every warehouse — just never the
database.

**Prerequisites:** Python 3.12 (dbt doesn't support 3.13+ yet —
`brew install python@3.12`).

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
| `run.sh`          | Build + test + serve docs. The main entry point |
| `.dbt-ensure-db.py` | Helper `run.sh` uses to detect (and offer to create) a missing database |
| `k8s/`            | Optional: run the same project inside Kubernetes. See [k8s/README.md](k8s/README.md) |

Generated at runtime and gitignored: `.venv/` (Python environment), `target/`
(compiled SQL and artifacts), `logs/`, `warehouse.duckdb` (the sandbox).

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

`profiles.yml` ships with targets for **duckdb**, **postgres**, **redshift**,
**snowflake**, **bigquery**, and **databricks**. `DBT_TARGET` picks one. Every
value has a default, so you only set what differs for you.

**Install the adapter for your warehouse** — the virtualenv starts with DuckDB
and Postgres:

```bash
.venv/bin/pip install dbt-snowflake   # or dbt-bigquery, dbt-redshift, dbt-databricks
```

### BigQuery

BigQuery also needs a service-account JSON file. Download it, then point at it:

```bash
DBT_TARGET=bigquery
DBT_BIGQUERY_PROJECT=my-gcp-project
DBT_BIGQUERY_KEYFILE=/absolute/path/to/service-account.json
```

For the Kubernetes path, mount it as a Secret — see [k8s/README.md](k8s/README.md).

## Everyday dbt commands

```bash
source .venv/bin/activate
export DBT_PROFILES_DIR="$PWD"

dbt build                        # seed + run + test, in dependency order
dbt run --select customer_orders # one model
dbt run --select stg_orders+     # a model and everything downstream of it
dbt test --select customer_orders
dbt compile                      # render the SQL without executing it
dbt docs generate && dbt docs serve
```

`--select` is the workhorse: it takes model names, `+` for upstream/downstream,
`tag:`, `path:`, and more.

## Running it on Kubernetes

Optional, and kept out of the way in [`k8s/`](k8s/README.md). It deploys dbt —
not a database — and connects to the same warehouse from `.env`:

```bash
k8s/spinup.sh
k8s/teardown.sh
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
