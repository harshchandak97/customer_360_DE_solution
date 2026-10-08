-- Warns when pairs are waiting for a human decision.
{{ config(severity='warn') }}
select * from {{ ref('review_queue') }}
