"""Check for, and optionally create, the target database.

Used by run.sh for Postgres and Redshift only — servers you own, where dbt
would otherwise fail on a missing database that it will never create itself.

  check   exit 0 = database exists, 3 = server up but database missing,
          1 = anything else (bad host, bad credentials); run.sh lets dbt
          report those, since its error messages are better than ours.
  create  create the database, exit 0 on success.
"""

import os
import sys

try:
    import psycopg2
    from psycopg2 import sql
except ImportError:  # adapter not installed; dbt will say so more clearly
    sys.exit(1)

# Databases that exist on a stock server and can be connected to in order to
# issue CREATE DATABASE: Postgres ships 'postgres', Redshift ships 'dev', and
# many setups also have one named after the login role.
MAINTENANCE_DBS = ("postgres", "dev", os.environ.get("PGUSER", ""))


def connect_kwargs():
    kwargs = {
        "host": os.environ["PGHOST"],
        "port": int(os.environ["PGPORT"]),
        "user": os.environ["PGUSER"],
        "connect_timeout": 10,
    }
    # Leave the password out entirely when empty, so trust auth still works.
    if os.environ.get("PGPASSWORD"):
        kwargs["password"] = os.environ["PGPASSWORD"]
    return kwargs


def maintenance_connection(kwargs):
    for dbname in MAINTENANCE_DBS:
        if not dbname:
            continue
        try:
            return psycopg2.connect(dbname=dbname, **kwargs)
        except psycopg2.OperationalError:
            continue
    return None


def check(kwargs, target):
    try:
        psycopg2.connect(dbname=target, **kwargs).close()
        return 0
    except psycopg2.OperationalError as exc:
        if "does not exist" not in str(exc):
            return 1

    conn = maintenance_connection(kwargs)
    if conn is None:
        return 1
    conn.close()
    return 3


def create(kwargs, target):
    conn = maintenance_connection(kwargs)
    if conn is None:
        return 1
    # CREATE DATABASE cannot run inside a transaction block.
    conn.autocommit = True
    try:
        with conn.cursor() as cur:
            cur.execute(sql.SQL("create database {}").format(sql.Identifier(target)))
    except psycopg2.Error as exc:
        print(exc, file=sys.stderr)
        return 1
    finally:
        conn.close()
    return 0


if __name__ == "__main__":
    action = sys.argv[1] if len(sys.argv) > 1 else "check"
    kwargs = connect_kwargs()
    target = os.environ["PGDB"]
    sys.exit(check(kwargs, target) if action == "check" else create(kwargs, target))
