-- BLOCKING: decide which records are worth comparing.
-- Comparing everyone with everyone grows explosively (1M records = ~500 billion pairs),
-- so we only compare records that share at least one "block key".

with records as (
    select * from {{ ref('int_customer_records') }}
    where not is_quarantined
),

block_keys as (
    select record_key, 'email:' || email as block_key from records where email is not null
    union all
    select record_key, 'phone:' || phone from records where phone is not null
    union all
    select record_key, 'name_city:' || lower(last_name) || '|' || lower(city)
    from records where last_name is not null and city is not null
),

pairs as (
    select
        a.record_key as record_key_a,
        b.record_key as record_key_b,
        string_agg(distinct split_part(a.block_key, ':', 1), ', ') as blocked_on
    from block_keys a
    join block_keys b
        on a.block_key = b.block_key
       and a.record_key < b.record_key   -- each pair once, never a record with itself
    group by 1, 2
)

select
    record_key_a || ' <> ' || record_key_b as pair_key,
    *
from pairs
