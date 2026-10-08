-- Warns when values were blanked because they were invalid or placeholders.
{{ config(severity='warn') }}
select record_key, field_issues
from {{ ref('int_customer_records') }}
where field_issues is not null
