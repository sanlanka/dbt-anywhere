# dbt anywhere

One dbt project that runs on **Postgres**, **DuckDB**, or any warehouse you
point it at. Nothing in the models is engine-specific, so the engine is a
one-flag swap — and the default setup needs no cloud account, no credentials,
and no signup.

## Quick start

```bash
./run.sh
```

The script finds or creates a local warehouse, then does `dbt seed` → `dbt run`
→ `dbt test`. For Postgres it tries, in order:

1. an existing Postgres on `localhost:5432` (creates the `dbt` role and
   `dbt_local` database if they're missing — it won't touch anything else)
2. `docker compose up` using the bundled `docker-compose.yml`
3. otherwise it tells you what to install

**Prerequisites:** Python 3.12 (dbt doesn't support 3.13+ yet), plus either a
local Postgres or Docker.

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
# postgres
PGPASSWORD=dbt psql -h localhost -U dbt -d dbt_local -c 'table analytics.customer_orders'

# duckdb
.venv/bin/python -c "import duckdb; print(duckdb.connect('warehouse.duckdb').sql('select * from analytics.customer_orders'))"
```

## Working on it

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
| `dbt_project.yml`     | Project config; staging → views, marts → tables    |
| `profiles.yml`        | Connection targets, all env-var driven             |
| `docker-compose.yml`  | Postgres 16, only if you don't have one already    |
| `seeds/`              | CSVs loaded into the warehouse by `dbt seed`       |
| `models/staging/`     | One cleaned-up model per raw source                |
| `models/marts/`       | Business-facing models built from staging          |
| `run.sh`              | Bootstrap + full build                             |

`warehouse.duckdb`, `target/`, `logs/`, and `.venv/` are gitignored — everything
tracked is source, and any clone rebuilds the warehouse from scratch.
