-- Rows set aside because they cannot be processed safely. Fix at the source and reload.
select
    record_key,
    source_system,
    source_record_id,
    quarantine_reason,
    full_name,
    email_original,
    phone_original,
    _source_file,
    _loaded_at
from {{ ref('int_customer_records') }}
where is_quarantined
