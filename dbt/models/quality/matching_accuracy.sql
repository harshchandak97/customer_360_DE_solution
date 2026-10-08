{{ config(enabled=var('evaluate_accuracy')) }}
-- Measures matching quality against the hand-labelled answer key.
-- Compares PAIRS of records: does the pipeline put the same two records together as the answer key?
--   precision = of the pairs we merged, how many were truly the same person   (wrong merges hurt this)
--   recall    = of the truly-same pairs, how many we merged                   (missed merges hurt this)

with truth as (
    select source_system || ':' || source_id as record_key, true_person_id
    from read_csv('{{ env_var("GROUND_TRUTH_PATH", "../data/expected/ground_truth.csv") }}',
                  header = true, all_varchar = true)
    where nullif(trim(source_id), '') is not null      -- quarantined rows are not part of matching
),

truth_pairs as (
    select a.record_key as key_a, b.record_key as key_b
    from truth a join truth b
      on a.true_person_id = b.true_person_id and a.record_key < b.record_key
),

predicted_pairs as (
    select a.record_key as key_a, b.record_key as key_b
    from {{ ref('customer_xref') }} a join {{ ref('customer_xref') }} b
      on a.customer_id = b.customer_id and a.record_key < b.record_key
),

review_pairs as (
    select record_key_a as key_a, record_key_b as key_b
    from {{ ref('int_scored_pairs') }} where decision = 'review'
),

counts as (
    select
        (select count(*) from predicted_pairs)                                        as predicted_pairs,
        (select count(*) from truth_pairs)                                            as true_pairs,
        (select count(*) from predicted_pairs p join truth_pairs t using (key_a, key_b)) as correct_pairs,
        (select count(*) from review_pairs r join truth_pairs t using (key_a, key_b)) as true_pairs_waiting_review
)

select
    *,
    round(correct_pairs / nullif(predicted_pairs, 0), 3) as precision,
    round(correct_pairs / nullif(true_pairs, 0), 3)      as recall,
    -- recall if a reviewer approves the true pairs sitting in the review queue
    round((correct_pairs + true_pairs_waiting_review) / nullif(true_pairs, 0), 3) as recall_after_review
from counts
