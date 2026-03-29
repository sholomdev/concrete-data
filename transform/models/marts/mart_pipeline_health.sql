{{
  config(
    materialized = 'table',
    tags         = ['mart', 'health'],
  )
}}

/*
  Aggregates daily row counts from the staging model so the Evidence
  /health page can show a 30-day row count chart without scanning the
  full requests table each time.
*/

with daily_counts as (

    select
        cast(created_at as date)       as complaint_date,
        count(*)                       as row_count,
        count(distinct complaint_type) as distinct_complaint_types,
        {{ countif("latitude is null") }}                               as missing_lat_count,
        {{ countif("borough = 'UNSPECIFIED' or borough is null") }}     as unspecified_borough_count

    from {{ ref('stg_311_requests') }}
    where created_at >= '2025-01-01'
    group by 1

),

with_stats as (

    select
        complaint_date,
        row_count,
        distinct_complaint_types,
        missing_lat_count,
        unspecified_borough_count,
        avg(row_count) over (
            order by complaint_date
            rows between 6 preceding and current row
        ) as row_count_7d_avg,
        lag(row_count) over (order by complaint_date) as prev_day_row_count

    from daily_counts

)

select
    complaint_date,
    row_count,
    prev_day_row_count,
    round(row_count_7d_avg, 0)        as row_count_7d_avg,
    distinct_complaint_types,
    missing_lat_count,
    unspecified_borough_count,
    round(
        {{ safe_divide('missing_lat_count', 'row_count') }} * 100, 2
    )                                  as missing_lat_pct,
    round(
        {{ safe_divide('abs(row_count - row_count_7d_avg)', 'nullif(row_count_7d_avg, 0)') }} * 100, 2
    )                                  as deviation_from_avg_pct

from with_stats
order by complaint_date desc
