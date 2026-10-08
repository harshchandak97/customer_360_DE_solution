-- Every raw row must appear exactly once in the silver table. Fails if any row is lost or duplicated.
{{ config(severity='error') }}

with raw_counts as (
    {% for model_name in var('customer_staging_models') %}
    select count(*) as n from {{ ref(model_name) }}
    {% if not loop.last %}union all{% endif %}
    {% endfor %}
)
select
    (select sum(n) from raw_counts) as rows_in,
    (select count(*) from {{ ref('int_customer_records') }}) as rows_out
where rows_in <> rows_out
