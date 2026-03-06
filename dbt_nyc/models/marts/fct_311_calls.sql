{{ config(
    materialized='incremental',
    unique_key='unique_key',
    partition_by={
      "field": "created_at",
      "data_type": "timestamp",
      "granularity": "day"
    },
    cluster_by=['agency', 'complaint_type']
) }}

WITH intermediate AS (
    SELECT * FROM {{ ref('int_resolution_metrics') }}
)

SELECT
    unique_key,
    created_at,
    closed_at,
    agency,
    complaint_type,
    borough,
    status,
    -- Metrics from the intermediate layer
    resolution_hours,
    is_within_sla,
    is_zombie_request,
    -- Geospatial data for maps
    latitude,
    longitude,
    geo_location
FROM intermediate

{% if is_incremental() %}
  -- Only look at data from the last 3 days to handle late-arriving status updates
  WHERE created_at >= (SELECT DATE_SUB(MAX(created_at), INTERVAL 3 DAY) FROM {{ this }})
{% endif %}