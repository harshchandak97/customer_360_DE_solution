-- SCORING: compare each candidate pair field by field, add up points, decide.
-- Points live in seeds/match_rules.csv and thresholds in dbt_project.yml, so tuning needs no code change.

with pairs as (
    select * from {{ ref('int_candidate_pairs') }}
),

records as (
    select * from {{ ref('int_customer_records') }}
),

rules as (
    select
        max(case when rule_name = 'email_match'  then points end) as email_pts,
        max(case when rule_name = 'phone_match'  then points end) as phone_pts,
        max(case when rule_name = 'dob_match'    then points end) as dob_pts,
        max(case when rule_name = 'name_similar' then points end) as name_pts,
        max(case when rule_name = 'city_match'   then points end) as city_pts,
        max(case when rule_name = 'dob_conflict' then points end) as dob_conflict_pts
    from {{ ref('match_rules') }}
),

compared as (
    select
        p.pair_key,
        p.record_key_a,
        p.record_key_b,
        p.blocked_on,
        a.full_name as name_a,
        b.full_name as name_b,
        round(jaro_winkler_similarity(lower(a.full_name), lower(b.full_name)), 3) as name_similarity,
        coalesce(a.email = b.email, false)                                   as email_match,
        coalesce(a.phone = b.phone, false)                                   as phone_match,
        coalesce(a.date_of_birth = b.date_of_birth, false)                   as dob_match,
        coalesce(a.date_of_birth <> b.date_of_birth, false)                  as dob_conflict,
        coalesce(a.city = b.city, false)                                     as city_match
    from pairs p
    join records a on p.record_key_a = a.record_key
    join records b on p.record_key_b = b.record_key
),

scored as (
    select
        c.*,
        c.name_similarity >= {{ var('name_similarity_min') }} as name_similar,
          case when c.email_match  then r.email_pts else 0 end
        + case when c.phone_match  then r.phone_pts else 0 end
        + case when c.dob_match    then r.dob_pts   else 0 end
        + case when c.name_similarity >= {{ var('name_similarity_min') }} then r.name_pts else 0 end
        + case when c.city_match   then r.city_pts  else 0 end
        + case when c.dob_conflict then r.dob_conflict_pts else 0 end         as match_score,
        -- human-readable explanation of the score
        concat_ws(', ',
            case when c.email_match  then 'email +' || r.email_pts end,
            case when c.phone_match  then 'phone +' || r.phone_pts end,
            case when c.dob_match    then 'dob +'   || r.dob_pts end,
            case when c.name_similarity >= {{ var('name_similarity_min') }}
                 then 'name ' || c.name_similarity || ' +' || r.name_pts end,
            case when c.city_match   then 'city +'  || r.city_pts end,
            case when c.dob_conflict then 'dob conflict ' || r.dob_conflict_pts end
        )                                                                     as match_reasons
    from compared c
    cross join rules r
)

select
    *,
    case
        when match_score >= {{ var('auto_match_threshold') }} then 'match'
        when match_score >= {{ var('review_threshold') }}     then 'review'
        else 'no_match'
    end as decision
from scored
