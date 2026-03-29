"""
NYC 311 Service Requests — dlt source
Socrata SODA API: https://data.cityofnewyork.us/resource/erm2-nwe9.json
"""

import dlt
from dlt.sources.helpers.rest_client import RESTClient
from dlt.sources.helpers.rest_client.paginators import OffsetPaginator
from dlt.common.time import ensure_pendulum_datetime
from typing import Iterator
import os


SOCRATA_BASE_URL = "https://data.cityofnewyork.us"
RESOURCE_ID = "erm2-nwe9"
PAGE_SIZE = 1000


def _build_client() -> RESTClient:
    app_token = dlt.secrets.get("sources.nyc_311.app_token", "")
    headers = {}
    if app_token:
        headers["X-App-Token"] = app_token

    return RESTClient(
        base_url=SOCRATA_BASE_URL,
        headers=headers,
        paginator=OffsetPaginator(
            limit=PAGE_SIZE,
            offset=0,
            limit_param="$limit",
            offset_param="$offset",
            total_path=None,
            stop_after_empty_page=True,
        ),
    )


@dlt.source(name="nyc_311")
def nyc_311_source(
    initial_start_date: str = "2025-01-01T00:00:00",
    end_date: str | None = None,
) -> Iterator:
    """
    Yields the 311 requests resource with incremental loading on updated_date.
    initial_start_date is only used on the very first run; thereafter dlt
    persists the cursor and only fetches newer records.

    end_date: optional ISO timestamp upper bound (inclusive). Useful for
    backfills — leaves the cursor unchanged so the next daily run continues
    from where it left off rather than from end_date.
    """
    yield requests_resource(
        initial_start_date=initial_start_date,
        end_date=end_date,
    )


@dlt.resource(
    name="requests",
    write_disposition="merge",
    primary_key="unique_key",
    columns={
        "unique_key":                 {"data_type": "text"},
        "created_date":               {"data_type": "timestamp"},
        "closed_date":                {"data_type": "timestamp"},
        "agency":                     {"data_type": "text"},
        "agency_name":                {"data_type": "text"},
        "complaint_type":             {"data_type": "text"},
        "descriptor":                 {"data_type": "text"},
        "location_type":              {"data_type": "text"},
        "incident_zip":               {"data_type": "text"},
        "incident_address":           {"data_type": "text"},
        "city":                       {"data_type": "text"},
        "status":                     {"data_type": "text"},
        "due_date":                   {"data_type": "timestamp"},
        "resolution_description":     {"data_type": "text"},
        "resolution_action_updated_date": {"data_type": "timestamp"},
        "community_board":            {"data_type": "text"},
        "bbl":                        {"data_type": "text"},
        "borough":                    {"data_type": "text"},
        "x_coordinate_state_plane":   {"data_type": "text"},
        "y_coordinate_state_plane":   {"data_type": "text"},
        "open_data_channel_type":     {"data_type": "text"},
        "park_facility_name":         {"data_type": "text"},
        "park_borough":               {"data_type": "text"},
        "latitude":                   {"data_type": "double"},
        "longitude":                  {"data_type": "double"},
        "updated_date":               {"data_type": "timestamp"},
    },
)
def requests_resource(
    updated_date: dlt.sources.incremental[str] = dlt.sources.incremental(
        "updated_date",
        initial_value="2025-01-01T00:00:00",
        range_start="closed",  # exclude the last fetched timestamp to avoid dupes
    ),
    initial_start_date: str = "2025-01-01T00:00:00",
    end_date: str | None = None,
) -> Iterator[dict]:
    """Incremental resource; cursor = updated_date."""
    client = _build_client()

    cursor_value = updated_date.last_value or initial_start_date
    where_clause = f"updated_date > '{cursor_value}'"
    if end_date:
        where_clause += f" AND updated_date <= '{end_date}'"

    params = {
        "$where": where_clause,
        "$order": "updated_date ASC",
    }

    for page in client.paginate(
        f"/resource/{RESOURCE_ID}.json",
        params=params,
    ):
        yield page
