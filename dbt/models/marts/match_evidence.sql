-- Why records were (or were not) linked: every compared pair with its score and reasons.
select
    p.pair_key,
    p.record_key_a,
    p.record_key_b,
    p.name_a,
    p.name_b,
    p.blocked_on,
    p.match_score,
    p.decision,
    p.match_reasons,
    p.email_match,
    p.phone_match,
    p.dob_match,
    p.dob_conflict,
    p.name_similarity,
    p.city_match
from {{ ref('int_scored_pairs') }} p
