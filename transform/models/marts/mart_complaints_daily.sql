{{
  config(
    materialized = 'table',
    partition_by = {
      "field": "complaint_date",
      "data_type": "date",
      "granularity": "day",
    } if target.type == 'bigquery' else none,
    cluster_by   = ['borough', 'complaint_type'] if target.type == 'bigquery' else none,
    tags         = ['mart', 'daily'],
  )
}}

with base as (

    select
        cast(created_at as date) as complaint_date,
        complaint_type,
        borough,
        agency,
        channel_type,
        status,
        count(*)                                  as total_requests,
        {{ countif("status = 'CLOSED'") }}        as closed_requests,
        {{ countif("status = 'OPEN'") }}          as open_requests

    from {{ ref('stg_311_requests') }}

    where created_at >= '2025-01-01'

    group by 1, 2, 3, 4, 5, 6

)

select
    complaint_date,
    complaint_type,
    borough,
    agency,
    channel_type,
    status,
    total_requests,
    closed_requests,
    open_requests,
    round(
        {{ safe_divide('closed_requests', 'total_requests') }} * 100, 2
    ) as close_rate_pct

from base
