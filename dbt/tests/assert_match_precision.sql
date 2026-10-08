-- Precision-first: fail the run if too many merges are wrong (wrong merges are a privacy risk).
{{ config(enabled=var('evaluate_accuracy')) }}
select * from {{ ref('matching_accuracy') }}
where precision < {{ var('min_match_precision') }}
