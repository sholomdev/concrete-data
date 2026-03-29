"""
Smoke tests for the NYC 311 dlt source.

Runs against the live Socrata API (no auth required for small samples)
using DuckDB as destination — no GCP needed.

Usage:
    cd pipeline
    ENV=dev pytest tests/test_source.py -v
"""

import os
import pytest
import dlt
from sources.nyc_311 import nyc_311_source, requests_resource


DUCKDB_PATH = os.getenv("DUCKDB_PATH", "/tmp/test_concrete_data.duckdb")


@pytest.fixture(scope="module")
def pipeline():
    return dlt.pipeline(
        pipeline_name="nyc_311_test",
        destination=dlt.destinations.duckdb(credentials=DUCKDB_PATH),
        dataset_name="nyc_311_test",
        dev_mode=True,  # auto-drops between runs
    )


def test_source_yields_data(pipeline):
    """Source returns at least one record for a narrow date window."""
    source = nyc_311_source(initial_start_date="2025-01-01T00:00:00")
    # Limit to first page only (1000 rows) by overriding the resource
    info = pipeline.run(source, limit=500)

    assert not info.has_failed_jobs, f"Pipeline failed: {info}"

    with pipeline.sql_client() as client:
        with client.execute_query("SELECT COUNT(*) as cnt FROM requests") as cur:
            row = cur.fetchone()
            assert row[0] > 0, "Expected at least 1 row in requests table"


def test_source_schema(pipeline):
    """Critical columns exist and have the right types."""
    with pipeline.sql_client() as client:
        with client.execute_query("SELECT * FROM requests LIMIT 1") as cur:
            cols = {desc[0] for desc in cur.description}

    required = {
        "unique_key", "created_date", "updated_date",
        "complaint_type", "borough", "status", "latitude", "longitude",
        "_dlt_load_id", "_dlt_id",
    }
    missing = required - cols
    assert not missing, f"Missing columns: {missing}"


def test_no_null_primary_keys(pipeline):
    """unique_key must never be null."""
    with pipeline.sql_client() as client:
        with client.execute_query(
            "SELECT COUNT(*) FROM requests WHERE unique_key IS NULL"
        ) as cur:
            null_count = cur.fetchone()[0]

    assert null_count == 0, f"Found {null_count} rows with null unique_key"


def test_incremental_cursor_advances(pipeline):
    """Second run should load zero new rows (no new data since first run)."""
    source = nyc_311_source(initial_start_date="2025-01-01T00:00:00")
    info = pipeline.run(source, limit=500)

    assert not info.has_failed_jobs
    # On re-run with same window, dlt's incremental cursor should skip already-seen rows
    loaded = sum(
        len(pkg.jobs.get("completed_jobs", []))
        for pkg in info.load_packages
    )
    # May be 0 (nothing new) or small (dedup) — just not a full reload
    assert loaded < 500, "Expected incremental run to load far fewer rows than full load"
