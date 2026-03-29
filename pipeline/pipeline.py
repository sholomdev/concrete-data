"""
concrete-data pipeline runner
Usage:
    ENV=dev  python pipeline.py          # DuckDB
    ENV=prod python pipeline.py          # BigQuery + GCS backup
    ENV=prod python pipeline.py --full   # force full refresh
"""

import os
import sys
import logging
from datetime import datetime, timezone
import dlt
from sources.nyc_311 import nyc_311_source

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
log = logging.getLogger("concrete-data.pipeline")

ENV = os.getenv("ENV", "dev").lower()
FULL_REFRESH = "--full" in sys.argv

INITIAL_START_DATE = os.getenv("INITIAL_START_DATE", "2025-01-01T00:00:00")
END_DATE = os.getenv("END_DATE", "") or None  # None = no upper bound (normal daily run)

GCP_PROJECT   = dlt.config.get("destination.bigquery.project", str, default="")
BQ_DATASET    = dlt.config.get("destination.bigquery.dataset_name", str, default="nyc_311_raw")
GCS_BUCKET    = dlt.config.get("destination.gcs_backup.bucket_url", str, default="")


def get_destination():
    if ENV == "prod":
        log.info("Destination: BigQuery (project=%s, dataset=%s)", GCP_PROJECT, BQ_DATASET)
        return dlt.destinations.bigquery(
            project=GCP_PROJECT,
            dataset_name=BQ_DATASET,
        )
    else:
        db_path = os.getenv("DUCKDB_PATH", "concrete_data_dev.duckdb")
        log.info("Destination: DuckDB (%s)", db_path)
        return dlt.destinations.duckdb(credentials=db_path)


def get_staging_destination():
    """GCS is used as a staging area / raw backup in prod only."""
    if ENV == "prod" and GCS_BUCKET:
        log.info("Staging/backup: GCS (%s)", GCS_BUCKET)
        return dlt.destinations.filesystem(bucket_url=GCS_BUCKET)
    return None


def run():
    log.info("=== concrete-data pipeline | ENV=%s | full=%s ===", ENV, FULL_REFRESH)

    destination = get_destination()
    staging     = get_staging_destination()

    pipeline = dlt.pipeline(
        pipeline_name="nyc_311",
        destination=destination,
        staging=staging,
        dataset_name=BQ_DATASET if ENV == "prod" else "nyc_311",
        dev_mode=False,
    )

    source = nyc_311_source(
        initial_start_date=INITIAL_START_DATE,
        end_date=END_DATE,
    )

    # Only override write_disposition for full refreshes.
    # For incremental runs, leave it unset so the resource default ("merge") applies.
    run_kwargs = {"write_disposition": "replace"} if FULL_REFRESH else {}

    load_info = pipeline.run(source, **run_kwargs)

    log.info("Load info:\n%s", load_info)

    # Surface any load errors as a non-zero exit so GitHub Actions fails the step
    if load_info.has_failed_jobs:
        log.error("Pipeline has failed jobs — see above for details")
        sys.exit(1)

    log.info("Pipeline completed successfully.")
    log.info(
        "Loaded %d completed jobs across %d packages",
        sum(len(p.jobs.get("completed_jobs", [])) for p in load_info.load_packages),
        len(load_info.load_packages),
    )


if __name__ == "__main__":
    run()
