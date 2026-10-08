-- Uncertain pairs for a data steward. They stay as separate customers until someone decides.
select
    p.pair_key,
    ca.customer_id as customer_id_a,
    cb.customer_id as customer_id_b,
    p.name_a,
    p.name_b,
    p.match_score,
    p.match_reasons,
    'pending' as review_status
from {{ ref('int_scored_pairs') }} p
join {{ ref('int_customer_clusters') }} ca on p.record_key_a = ca.record_key
join {{ ref('int_customer_clusters') }} cb on p.record_key_b = cb.record_key
where p.decision = 'review'
