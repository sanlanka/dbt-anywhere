# A walkthrough, with Postgres

What dbt is, what this project builds, and how to see all of it for yourself in
a Postgres database. Everything below is real output from running it.

## What dbt is

dbt turns **SELECT statements into tables and views in your warehouse**, in the
right order, with tests.

You write `models/customer_orders.sql` containing a query. dbt wraps it in
`create table as` and runs it. Nothing more magical than that — the value is in
the four things it adds:

| | |
|---|---|
| **Dependencies** | You write `{{ ref('stg_orders') }}` instead of a table name. dbt reads those references, builds a graph, and runs models in order — no scheduling by hand |
| **Tests** | Declare "`order_id` is unique" in YAML; dbt turns it into a query that must return zero rows |
| **Environments** | The same SQL runs against dev and prod, because the connection lives outside the code |
| **Docs** | The DAG, the compiled SQL, and column lineage, generated from the project |

dbt does not move data or run a database. Your data is already in the warehouse;
dbt reshapes it in place.

## What this project builds

```
seeds/raw_customers.csv ─┐
seeds/raw_orders.csv    ─┴─► stg_customers ─┐
                             stg_orders    ─┴─► customer_orders
                              (views)            (table)
```

**Seeds** — two small CSVs, loaded by `dbt seed`. In a real project raw data is
already in the warehouse; seeds stand in for it here so the example runs
anywhere.

**Staging** (`models/staging/`) — one lightly-cleaned model per raw table: cast
types, add a `full_name`. Views, so they cost nothing to rebuild.

**Marts** (`models/marts/`) — `customer_orders`, one row per customer with
completed-order counts and lifetime value. A table, because it's what gets
queried.

Raw → staging → marts is the standard dbt layout, and it's worth keeping.

## Run it

```bash
cp .env.example .env
```

```bash
DBT_TARGET=postgres
DBT_PG_HOST=localhost
DBT_PG_USER=your_username     # `whoami` on Homebrew / Postgres.app
DBT_PG_PASSWORD=
DBT_PG_DATABASE=analytics
DBT_SCHEMA=analytics
```

The database has to exist — dbt creates schemas, never databases. `spinup.sh`
offers to create it if it's missing (or `createdb analytics` yourself).

```bash
./spinup.sh
```

## Check it in Postgres

### 1. What dbt created

```
$ psql -d analytics -c "select table_name, table_type from information_schema.tables
                        where table_schema='analytics' order by table_type, table_name;"

   table_name    | table_type
-----------------+------------
 customer_orders | BASE TABLE
 raw_customers   | BASE TABLE
 raw_orders      | BASE TABLE
 stg_customers   | VIEW
 stg_orders      | VIEW
```

Five objects from five files. The staging models are **views** and the mart is a
**table** — that's the `+materialized` setting in `dbt_project.yml`, and it's a
one-word change to flip either.

### 2. The seeds, loaded as-is

```
$ psql -d analytics -c "select * from analytics.raw_orders limit 4;"

 order_id | customer_id | order_date | amount |  status
----------+-------------+------------+--------+-----------
      101 |           1 | 2024-03-01 |  49.99 | completed
      102 |           1 | 2024-03-14 |    120 | completed
      103 |           2 | 2024-03-18 |   15.5 | returned
      104 |           3 | 2024-04-02 |     89 | completed
```

### 3. Staging: cleaned, not reshaped

```
$ psql -d analytics -c "select * from analytics.stg_customers limit 3;"

 customer_id | first_name | last_name |  full_name   | signup_date
-------------+------------+-----------+--------------+-------------
           1 | Ada        | Lovelace  | Ada Lovelace | 2024-01-15
           2 | Alan       | Turing    | Alan Turing  | 2024-02-03
           3 | Grace      | Hopper    | Grace Hopper | 2024-02-27
```

Same grain as the raw table, with `full_name` added and dates cast.

### 4. The mart: the actual answer

```
$ psql -d analytics -c "select customer_id, full_name, completed_orders, lifetime_value
                        from analytics.customer_orders order by lifetime_value desc;"

 customer_id |     full_name     | completed_orders | lifetime_value
-------------+-------------------+------------------+----------------
           3 | Grace Hopper      |                2 |         329.75
           1 | Ada Lovelace      |                2 |         169.99
           4 | Katherine Johnson |                1 |          73.25
           2 | Alan Turing       |                0 |              0
           5 | Edsger Dijkstra   |                0 |              0
```

Two details worth checking against the raw data, because they show the model is
doing real work:

- **Alan Turing shows 0**, though `raw_orders` has order 103 for him — it's
  `returned`, and the model filters to `status = 'completed'`.
- **Edsger Dijkstra appears at all**, with no orders anywhere. That's the `left
  join`: customers with nothing still get a row, with `coalesce(..., 0)`.

Change the left join to an inner join and Dijkstra disappears. That's the kind
of bug the tests below exist to catch.

## See what dbt actually ran

`{{ ref() }}` is not SQL — dbt compiles it to a real name. The compiled file is
in the pod:

```
$ kubectl exec -n data deploy/dbt-runner -- \
    sed -n 1,6p /tmp/target/compiled/dbt_anywhere/models/staging/stg_orders.sql

with source as (

    select * from "analytics"."analytics"."raw_orders"

)
```

`{{ ref('raw_orders') }}` became `"analytics"."analytics"."raw_orders"` —
database, schema, table, all from your `.env`. Point `.env` at a different
warehouse and the same model compiles to a different name, with no code change.

## Run the tests

```
$ kubectl exec -n data deploy/dbt-runner -- dbt test --select stg_orders

PASS accepted_values_stg_orders_status__completed__returned__pending
PASS not_null_stg_orders_customer_id
PASS not_null_stg_orders_order_id
PASS relationships_stg_orders_customer_id__customer_id__ref_stg_customers_
PASS unique_stg_orders_order_id
Done. PASS=5 WARN=0 ERROR=0 SKIP=0 NO-OP=0 REUSED=0 TOTAL=5
```

Those five come from ten lines of YAML in `models/staging/_staging.yml`:

```yaml
      - name: order_id
        tests: [unique, not_null]
      - name: customer_id
        tests:
          - not_null
          - relationships:
              to: ref('stg_customers')
              field: customer_id
      - name: status
        tests:
          - accepted_values:
              values: [completed, returned, pending]
```

`relationships` is the one to notice: it fails if any order references a
customer that doesn't exist — a foreign key you get without declaring one.

### Watch a test fail

Break the data on purpose:

```
$ psql -d analytics -c "insert into analytics.raw_orders
                        values (101, 1, '2024-06-01', 10.00, 'completed');"

$ kubectl exec -n data deploy/dbt-runner -- dbt test --select stg_orders

FAIL 1 unique_stg_orders_order_id
  compiled code at /tmp/target/compiled/.../unique_stg_orders_order_id.sql
Done. PASS=4 WARN=0 ERROR=1 SKIP=0 NO-OP=0 REUSED=0 TOTAL=5
```

`FAIL 1` means one row broke the rule. The compiled path is the query that found
it — run it yourself to see the offending rows. Put it back:

```bash
kubectl exec -n data deploy/dbt-runner -- dbt seed
```

## Change something

The project is mounted into the pod, so an edit on your Mac needs a re-run, not
a rebuild. Add a column to `models/marts/customer_orders.sql`:

```sql
    coalesce(t.lifetime_value, 0) / nullif(t.completed_orders, 0) as avg_order_value,
```

```bash
kubectl exec -n data deploy/dbt-runner -- dbt run --select customer_orders
psql -d analytics -c 'select full_name, avg_order_value from analytics.customer_orders;'
```

`--select customer_orders+` rebuilds it and everything downstream;
`+customer_orders` rebuilds everything it depends on first.

## Where to go next

- **[dbt Fundamentals](https://learn.getdbt.com/courses/dbt-fundamentals)** —
  free official course, a few hours
- **[Sources](https://docs.getdbt.com/docs/build/sources)** — how to point at
  tables already in your warehouse instead of seeds. This is the first thing
  you'll want for real data
- **[Materializations](https://docs.getdbt.com/docs/build/materializations)** —
  view, table, incremental, and when each is right
- **[Best practices](https://docs.getdbt.com/best-practices)** — why the
  staging/marts split exists

Back to the [main README](README.md).
