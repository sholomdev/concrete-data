{{ config(materialized='view') }}

WITH source AS (
    SELECT * FROM {{ source('nyc_raw', 'nyc_311_data') }}
),

renamed AS (
    SELECT
        unique_key,
        -- Timestamps
        CAST(created_date AS TIMESTAMP) AS created_at,
        CAST(closed_date AS TIMESTAMP) AS closed_at,
        CAST(due_date AS TIMESTAMP) AS due_at,
        
        -- Categorization
        UPPER(agency) AS agency,
        agency_name,
        complaint_type,
        descriptor,
        
        -- Location
        location_type,
        incident_zip,
        UPPER(borough) AS borough,
        status,
        resolution_description,
        
        -- Geospatial
        CAST(latitude AS FLOAT64) AS latitude,
        CAST(longitude AS FLOAT64) AS longitude,
        -- Create a native BigQuery Geography object
        ST_GEOGPOINT(CAST(longitude AS FLOAT64), CAST(latitude AS FLOAT64)) AS geo_location
    FROM source
)

SELECT * FROM renamed