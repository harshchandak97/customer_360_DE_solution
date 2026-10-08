-- Every usable (non-quarantined) record must belong to exactly one customer.
select r.record_key
from {{ ref('int_customer_records') }} r
left join {{ ref('customer_xref') }} x using (record_key)
where not r.is_quarantined
  and x.record_key is null
