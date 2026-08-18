# dbt runner image. Python 3.12 because dbt does not support 3.13+ yet — the
# same constraint spinup.sh enforces locally, so both paths run one version.
FROM python:3.12-slim

# Which warehouse adapters to install. Kept short by default to keep the image
# small; add yours here or via skaffold.yaml's buildArgs, e.g.
#   DBT_ADAPTERS="dbt-snowflake dbt-bigquery dbt-redshift dbt-databricks"
ARG DBT_ADAPTERS="dbt-postgres dbt-duckdb"

# git is required by `dbt deps` — dbt packages are git clones.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends git; \
    rm -rf /var/lib/apt/lists/*; \
    pip install --no-cache-dir dbt-core==1.12.2 ${DBT_ADAPTERS}

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# The project itself is mounted at /dbt by the chart, not baked into the image,
# so editing a model on your Mac only needs a re-run, never a rebuild.
WORKDIR /dbt
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
