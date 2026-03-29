{{
  config(
    materialized = 'table',
    tags         = ['mart', 'open'],
  )
}}

with open_requests as (

    select
        unique_key,
        complaint_type,
        borough,
        agency,
        zip_code,
        address,
        latitude,
        longitude,
        created_at,
        due_at,
        updated_at,
        channel_type,
        resolution_description,
        {{ timestamp_diff_hours('current_timestamp()', 'created_at') }} as age_hours

    from {{ ref('stg_311_requests') }}

    where status = 'OPEN'
      and created_at >= '2025-01-01'

),

bucketed as (

    select
        *,
        case
            when age_hours < 24   then '< 1 day'
            when age_hours < 72   then '1–3 days'
            when age_hours < 168  then '3–7 days'
            when age_hours < 720  then '1–4 weeks'
            when age_hours < 2160 then '1–3 months'
            else                       '3+ months'
        end as age_bucket,

        case
            when due_at is not null and due_at < current_timestamp() then true
            else false
        end as is_overdue

    from open_requests

)

select * from bucketed
