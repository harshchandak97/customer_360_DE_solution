-- Over-merging guardrail: one "person" with too many records usually means a bad link
-- (e.g. a shared dummy value chaining strangers together).
{{ config(severity='warn') }}
select customer_id, max(cluster_size) as cluster_size
from {{ ref('int_customer_clusters') }}
group by customer_id
having max(cluster_size) > {{ var('max_expected_cluster_size') }}
