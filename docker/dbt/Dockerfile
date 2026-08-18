# dbt runner image. Python 3.12 because dbt does not support 3.13+ yet — the
# same constraint spinup.sh enforces locally, so both paths run one version.
FROM python:3.12-slim

RUN set -eux; \
    pip install --no-cache-dir \
      dbt-core==1.12.2 \
      dbt-postgres==1.11.0 \
      dbt-duckdb==1.11.0

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# The project itself is mounted at /dbt by the chart, not baked into the image,
# so editing a model on your Mac only needs a re-run, never a rebuild.
WORKDIR /dbt
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
