{# 
  safe_divide: null-safe division, handles BigQuery SAFE_DIVIDE and DuckDB equivalents
#}
{% macro safe_divide(numerator, denominator) %}
  {% if target.type == 'bigquery' %}
    safe_divide({{ numerator }}, {{ denominator }})
  {% else %}
    case when {{ denominator }} = 0 then null
         else ({{ numerator }})::double / ({{ denominator }})::double
    end
  {% endif %}
{% endmacro %}


{#
  countif: BigQuery COUNTIF vs DuckDB COUNT(CASE ...)
#}
{% macro countif(condition) %}
  {% if target.type == 'bigquery' %}
    countif({{ condition }})
  {% else %}
    count(case when {{ condition }} then 1 end)
  {% endif %}
{% endmacro %}


{#
  approx_percentile: BigQuery APPROX_QUANTILES vs DuckDB APPROX_QUANTILE
#}
{% macro approx_percentile(column, percentile) %}
  {% if target.type == 'bigquery' %}
    approx_quantiles({{ column }}, 100)[offset({{ (percentile * 100) | int }})]
  {% else %}
    approx_quantile({{ column }}, {{ percentile }})
  {% endif %}
{% endmacro %}


{#
  timestamp_diff_hours: BigQuery TIMESTAMP_DIFF vs DuckDB DATEDIFF
#}
{% macro timestamp_diff_hours(end_ts, start_ts) %}
  {% if target.type == 'bigquery' %}
    timestamp_diff({{ end_ts }}, {{ start_ts }}, hour)
  {% else %}
    datediff('hour', {{ start_ts }}, {{ end_ts }})
  {% endif %}
{% endmacro %}
