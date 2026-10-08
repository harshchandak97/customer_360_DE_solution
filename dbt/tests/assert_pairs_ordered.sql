-- A record is never paired with itself, and each pair appears in one direction only.
select * from {{ ref('int_candidate_pairs') }}
where record_key_a >= record_key_b
