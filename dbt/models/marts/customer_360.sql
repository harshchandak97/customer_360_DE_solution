-- GOLD: one row per customer, the "golden record".
-- Survivorship = which value wins when a customer's records disagree:
--   identity fields (name, date of birth): most trusted source first, then most recent
--   contact fields (email, phone, city):    most recent first, then most trusted source
-- Empty values never win over filled ones.

with records as (
    select
        c.customer_id,
        r.*,
        t.trust_rank
    from {{ ref('int_customer_clusters') }} c
    join {{ ref('int_customer_records') }} r using (record_key)
    left join {{ ref('source_trust') }} t on r.source_system = t.source_system
),

pending_review as (
    select customer_id_a as customer_id from {{ ref('review_queue') }}
    union
    select customer_id_b from {{ ref('review_queue') }}
)

select
    customer_id,

    first(first_name    order by trust_rank, source_updated_at desc) filter (where first_name is not null)    as first_name,
    first(last_name     order by trust_rank, source_updated_at desc) filter (where last_name is not null)     as last_name,
    first(date_of_birth order by trust_rank, source_updated_at desc) filter (where date_of_birth is not null) as date_of_birth,

    first(email order by source_updated_at desc, trust_rank) filter (where email is not null) as email,
    first(phone order by source_updated_at desc, trust_rank) filter (where phone is not null) as phone,
    first(city  order by source_updated_at desc, trust_rank) filter (where city  is not null) as city,

    -- lineage: which record each key value came from
    first(record_key order by trust_rank, source_updated_at desc) filter (where last_name is not null) as name_from_record,
    first(record_key order by source_updated_at desc, trust_rank) filter (where email is not null)     as email_from_record,

    count(*)                                                    as source_record_count,
    string_agg(distinct source_system, ', ' order by source_system) as source_systems,
    string_agg(record_key, ', ' order by record_key)            as source_records,
    max(source_updated_at)                                      as last_updated_at,
    customer_id in (select customer_id from pending_review)     as has_pending_review
from records
group by customer_id
