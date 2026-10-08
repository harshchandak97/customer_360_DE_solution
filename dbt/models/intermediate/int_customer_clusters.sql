-- GROUPING: turn matched pairs into people.
-- If A matches B and B matches C, all three are one person, even though A and C were never compared.
-- This is "connected components": follow match links until no new records are reached.

with recursive

records as (
    select record_key, source_system, source_record_id
    from {{ ref('int_customer_records') }}
    where not is_quarantined
),

-- only auto-matches link records; "review" pairs stay separate until a human decides
edges as (
    select record_key_a as from_key, record_key_b as to_key
    from {{ ref('int_scored_pairs') }} where decision = 'match'
    union
    select record_key_b, record_key_a
    from {{ ref('int_scored_pairs') }} where decision = 'match'
),

-- start from every record, keep walking along match links
reachable(start_key, reached_key) as (
    select record_key, record_key from records
    union                                   -- UNION (not UNION ALL) stops when nothing new is found
    select r.start_key, e.to_key
    from reachable r
    join edges e on r.reached_key = e.from_key
),

-- every record in a group reaches the same set, so the smallest key names the group
clusters as (
    select start_key as record_key, min(reached_key) as cluster_anchor
    from reachable
    group by start_key
)

select
    r.record_key,
    r.source_system,
    r.source_record_id,
    -- ID derived from the group's anchor record: same input -> same ID on every run
    'C360-' || upper(substr(md5(c.cluster_anchor), 1, 10)) as customer_id,
    c.cluster_anchor,
    count(*) over (partition by c.cluster_anchor)           as cluster_size
from records r
join clusters c using (record_key)
