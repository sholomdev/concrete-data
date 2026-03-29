{{
  config(
    materialized = 'table',
    partition_by = {
      "field": "complaint_date",
      "data_type": "date",
      "granularity": "day",
    } if target.type == 'bigquery' else none,
    cluster_by   = ['borough', 'complaint_type'] if target.type == 'bigquery' else none,
    tags         = ['mart', 'resolution'],
  )
}}

with resolved as (

    select
        complaint_type,
        borough,
        agency,
        cast(created_at as date)                          as complaint_date,
        {{ timestamp_diff_hours('closed_at', 'created_at') }} as hours_to_close

    from {{ ref('stg_311_requests') }}

    where
        status     = 'CLOSED'
        and closed_at  is not null
        and created_at is not null
        and closed_at  > created_at
        -- exclude extreme outliers (> 1 year)
        and {{ timestamp_diff_hours('closed_at', 'created_at') }} < 8760

),

agg as (

    select
        complaint_type,
        borough,
        agency,
        complaint_date,
        count(*)                               as resolved_requests,
        round(avg(hours_to_close),  1)         as avg_hours_to_close,
        round({{ approx_percentile('hours_to_close', 0.5) }}, 1) as median_hours_to_close,
        round({{ approx_percentile('hours_to_close', 0.9) }}, 1) as p90_hours_to_close,
        min(hours_to_close)                    as min_hours_to_close,
        max(hours_to_close)                    as max_hours_to_close

    from resolved
    group by 1, 2, 3, 4

)

select * from agg
