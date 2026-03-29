---
title: Insights
---

```sql resolution_by_type
select
    complaint_type,
    round(avg(avg_hours_to_close), 1)    as avg_hours,
    round(avg(median_hours_to_close), 1) as median_hours,
    round(avg(p90_hours_to_close), 1)    as p90_hours,
    sum(resolved_requests)               as total_resolved
from mart_resolution_time
where complaint_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
group by 1
having total_resolved >= 50
order by avg_hours desc
limit 20
```

```sql resolution_by_borough
select
    borough,
    round(avg(avg_hours_to_close), 1)    as avg_hours,
    sum(resolved_requests)               as total_resolved
from mart_resolution_time
where complaint_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
  and borough != 'UNSPECIFIED'
group by 1
order by avg_hours
```

```sql weekly_trend
select
    DATE_TRUNC(complaint_date, WEEK)      as week,
    complaint_type,
    sum(total_requests)                  as requests
from mart_complaints_daily
where complaint_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
group by 1, 2
```

```sql open_by_age
select
    age_bucket,
    count(*)          as open_count,
    countif(is_overdue) as overdue_count,
    borough
from mart_open_requests
group by 1, 4
order by
    case age_bucket
        when '< 1 day'    then 1
        when '1–3 days'   then 2
        when '3–7 days'   then 3
        when '1–4 weeks'  then 4
        when '1–3 months' then 5
        else 6
    end,
    borough
```

```sql channel_mix
select
    channel_type,
    sum(total_requests)  as total_requests,
    round(
        100.0 * sum(total_requests) / sum(sum(total_requests)) over (), 1
    )                    as share_pct
from mart_complaints_daily
where complaint_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
group by 1
order by 2 desc
```

## Resolution time by complaint type

Slowest-resolved complaint types (90-day window, min 50 resolved).

<DataTable
  data={resolution_by_type}
  rows=15
  search=true
>
  <Column id="complaint_type" title="Complaint type" />
  <Column id="avg_hours"      title="Avg hours"    fmt="num1" />
  <Column id="median_hours"   title="Median hours" fmt="num1" />
  <Column id="p90_hours"      title="P90 hours"    fmt="num1" />
  <Column id="total_resolved" title="Resolved"     fmt="num0" />
</DataTable>

## Resolution time by borough

<BarChart
  data={resolution_by_borough}
  x="borough"
  y="avg_hours"
  title="Average hours to close — by borough (90 days)"
  yAxisTitle="Hours"
  colorPalette={['#1D9E75']}
/>

## Open requests by age

<BarChart
  data={open_by_age}
  x="age_bucket"
  y="open_count"
  series="borough"
  type="stacked"
  title="Open requests by age bucket and borough"
/>

## How are requests submitted?

<BarChart
  data={channel_mix}
  x="channel_type"
  y="total_requests"
  title="Request channel mix — last 30 days"
  colorPalette={['#7F77DD']}
/>
