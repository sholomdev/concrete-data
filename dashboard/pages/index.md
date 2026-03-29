---
title: NYC 311 Dashboard
---

```sql daily_totals
select
    complaint_date,
    sum(total_requests)  as total_requests,
    sum(closed_requests) as closed_requests,
    sum(open_requests)   as open_requests
from mart_complaints_daily
where complaint_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
group by 1
order by 1
```

```sql top_complaints
select
    complaint_type,
    sum(total_requests) as total_requests
from mart_complaints_daily
where complaint_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
group by 1
order by 2 desc
limit 10
```

```sql borough_totals
select
    borough,
    sum(total_requests)  as total_requests,
    round(avg(close_rate_pct), 1) as avg_close_rate
from mart_complaints_daily
where complaint_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
  and borough != 'UNSPECIFIED'
group by 1
order by 2 desc
```

```sql kpis
select
    sum(total_requests)                   as total_30d,
    sum(open_requests)                    as open_30d,
    round(avg(close_rate_pct), 1)         as avg_close_rate,
    max(complaint_date)                   as last_updated
from mart_complaints_daily
where complaint_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
```

<BigValue
  data={kpis}
  value="total_30d"
  title="Requests (30d)"
  fmt="num0"
/>
<BigValue
  data={kpis}
  value="open_30d"
  title="Currently open"
  fmt="num0"
/>
<BigValue
  data={kpis}
  value="avg_close_rate"
  title="Close rate"
  fmt="pct1"
/>
<BigValue
  data={kpis}
  value="last_updated"
  title="Last updated"
  fmt="date"
/>

---

## Daily request volume

<LineChart
  data={daily_totals}
  x="complaint_date"
  y="total_requests"
  yAxisTitle="Requests"
  title="Total 311 requests — last 30 days"
/>

## Top complaint types

<BarChart
  data={top_complaints}
  x="complaint_type"
  y="total_requests"
  swapXY=true
  title="Top 10 complaint types — last 30 days"
  colorPalette={['#378ADD']}
/>

## Requests by borough

<BarChart
  data={borough_totals}
  x="borough"
  y="total_requests"
  title="Requests by borough — last 30 days"
/>
