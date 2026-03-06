import dlt
from dlt.sources.helpers import requests

@dlt.resource(write_disposition="append", primary_key="unique_key")
def nyc_311_resource(
    created_date=dlt.sources.incremental("created_date", initial_value="2026-01-01T00:00:00")
):
    url = "https://data.cityofnewyork.us/resource/erm2-nwe9.json"
    params = {
        "$where": f"created_date > '{created_date.last_value}'",
        "$limit": 5000,
        "$$app_token": dlt.secrets.get("nyc_token")
    }
    response = requests.get(url, params=params)
    response.raise_for_status()
    yield response.json()

if __name__ == "__main__":
    pipeline = dlt.pipeline(
        pipeline_name="nyc_311",
        destination="bigquery",
        dataset_name="nyc_311_raw"
    )
    pipeline.run(nyc_311_resource())