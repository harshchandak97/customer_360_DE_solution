-- Crosswalk: every usable source record -> the customer it belongs to.
-- Lets any system translate its own ID into the unified customer_id (and back).
select
    c.record_key,
    c.source_system,
    c.source_record_id,
    c.customer_id,
    c.cluster_size,
    case when c.cluster_size > 1 then 'matched' else 'single_record' end as link_type
from {{ ref('int_customer_clusters') }} c
