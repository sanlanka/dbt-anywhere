# dbt + DuckDB, running locally

A complete **dbt** project that runs entirely on your laptop — no warehouse, no
credentials, no containers. [DuckDB](https://duckdb.org) is the engine and the
whole "warehouse" is a single file (`warehouse.duckdb`).

## Quick start

```bash
./run.sh
```

That's it. The script creates the virtualenv on first run, installs dbt, then
does `dbt seed` → `dbt run` → `dbt test`.

**Prerequisites:** Python 3.12 (dbt doesn't support 3.13+ yet).

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
.venv/bin/python -c "import duckdb; print(duckdb.connect('warehouse.duckdb').sql('select * from customer_orders'))"
```

Or open the file in the DuckDB CLI (`brew install duckdb`):

```bash
duckdb warehouse.duckdb
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
| `profiles.yml`        | The DuckDB connection. Lives in-repo, no secrets   |
| `seeds/`              | CSVs loaded into the warehouse by `dbt seed`       |
| `models/staging/`     | One cleaned-up model per raw source                |
| `models/marts/`       | Business-facing models built from staging          |
| `run.sh`              | Bootstrap + full build                             |

`warehouse.duckdb`, `target/`, `logs/`, and `.venv/` are gitignored — everything
tracked is source, and any clone rebuilds the warehouse from scratch.

## Swapping in a real warehouse

The models are plain SQL. To point them at Snowflake/BigQuery/Postgres, install
that adapter and replace the `outputs.dev` block in `profiles.yml` — the models,
tests, and DAG carry over unchanged.
