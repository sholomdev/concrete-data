---
title: Pipeline health
---

```sql health_30d
select
    complaint_date,
    row_count,
    row_count_7d_avg,
    deviation_from_avg_pct,
    missing_lat_pct,
    distinct_complaint_types,
    unspecified_borough_count
from mart_pipeline_health
order by complaint_date desc
limit 30
```

```sql latest
select
    complaint_date                               as last_load_date,
    row_count                                    as todays_rows,
    row_count_7d_avg                             as avg_rows_7d,
    deviation_from_avg_pct                       as deviation_pct,
    missing_lat_pct,
    distinct_complaint_types
from mart_pipeline_health
order by complaint_date desc
limit 1
```

```sql anomaly_days
select
    complaint_date,
    row_count,
    row_count_7d_avg,
    deviation_from_avg_pct
from mart_pipeline_health
where abs(deviation_from_avg_pct) > 30
order by complaint_date desc
limit 10
```

```sql dbt_test_results
select
    test_name,
    status,
    failures,
    model_unique_id  as model,
    detected_at
from elementary_test_results
order by detected_at desc
limit 50
```

<BigValue
  data={latest}
  value="todays_rows"
  title="Rows loaded today"
  fmt="num0"
/>
<BigValue
  data={latest}
  value="avg_rows_7d"
  title="7-day avg rows"
  fmt="num0"
/>
<BigValue
  data={latest}
  value="deviation_pct"
  title="Deviation from avg"
  fmt="pct1"
/>
<BigValue
  data={latest}
  value="missing_lat_pct"
  title="Missing lat/lon"
  fmt="pct1"
/>

---

## Daily row count — last 30 days

<BarChart
  data={health_30d}
  x="complaint_date"
  y="row_count"
  y2="row_count_7d_avg"
  y2SeriesType="line"
  title="Rows loaded per day vs 7-day rolling average"
  yAxisTitle="Rows"
  colorPalette={['#B5D4F4', '#185FA5']}
/>

## Anomaly days (>30% deviation from 7d avg)

{#if anomaly_days.length === 0}
  <Note>No anomalies detected in the last 30 days.</Note>
{:else}
  <DataTable data={anomaly_days}>
    <Column id="complaint_date"        title="Date" fmt="date" />
    <Column id="row_count"             title="Rows loaded" fmt="num0" />
    <Column id="row_count_7d_avg"      title="7d avg" fmt="num0" />
    <Column id="deviation_from_avg_pct" title="Deviation" fmt="pct1" contentType="delta" />
  </DataTable>
{/if}

## dbt test results (last 50 runs)

<DataTable data={dbt_test_results} rows=20 search=true>
  <Column id="detected_at" title="Run at"   fmt="datetime" />
  <Column id="test_name"   title="Test"     />
  <Column id="model"       title="Model"    />
  <Column id="status"      title="Status"   contentType="colorscale" />
  <Column id="failures"    title="Failures" fmt="num0" />
</DataTable>
