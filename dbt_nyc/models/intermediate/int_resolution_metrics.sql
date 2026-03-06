{{ config(materialized='ephemeral') }} 
-- 'ephemeral' means it doesn't create a table in BigQuery, it just acts as a reusable snippet.

WITH staging AS (
    SELECT * FROM {{ ref('stg_nyc311') }}
)

SELECT
    *,
    TIMESTAMP_DIFF(closed_at, created_at, HOUR) as resolution_hours,
    CASE 
        WHEN closed_at <= due_at THEN TRUE
        WHEN closed_at > due_at THEN FALSE
        ELSE NULL 
    END as is_within_sla,
    CASE 
        WHEN status = 'Open' AND TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), created_at, DAY) > 30 THEN TRUE 
        ELSE FALSE 
    END as is_zombie_request
FROM staging