-- Warns (does not fail the run) when any rows were quarantined, so someone looks at them.
{{ config(severity='warn') }}
select * from {{ ref('quarantine_records') }}
