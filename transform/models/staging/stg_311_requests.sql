{{
  config(
    materialized = 'view',
    tags         = ['staging'],
  )
}}

with source as (

    select * from {{ source('nyc_311_raw', 'requests') }}

),

cleaned as (

    select
        unique_key,

        -- Timestamps
        cast(created_date as timestamp)                   as created_at,
        cast(closed_date  as timestamp)                   as closed_at,
        cast(due_date     as timestamp)                   as due_at,
        cast(updated_date as timestamp)                   as updated_at,
        cast(resolution_action_updated_date as timestamp) as resolution_updated_at,

        -- Classification
        trim(upper(complaint_type))  as complaint_type,
        trim(descriptor)             as descriptor,
        trim(upper(agency))          as agency,
        trim(agency_name)            as agency_name,
        trim(upper(status))          as status,
        trim(upper(borough))         as borough,
        trim(community_board)        as community_board,
        trim(open_data_channel_type) as channel_type,
        trim(location_type)          as location_type,

        -- Location
        trim(incident_zip)                    as zip_code,
        trim(incident_address)                as address,
        trim(city)                            as city,
        cast(latitude  as {{ dbt.type_float() }}) as latitude,
        cast(longitude as {{ dbt.type_float() }}) as longitude,

        -- Resolution
        trim(resolution_description)          as resolution_description,

        -- dlt metadata
        -- _dlt_load_id is a Unix epoch float stored as a string.
        -- We expose it raw; use loaded_at for recency checks.
        _dlt_load_id,
        _dlt_id,
        cast(updated_date as timestamp) as loaded_at   -- proxy for dlt load recency

    from source

    where unique_key is not null

)

select * from cleaned
