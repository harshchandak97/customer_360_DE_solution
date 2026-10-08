-- All sources in one standard table (silver layer).
-- Every raw row appears exactly once: good rows are ready for matching,
-- broken rows are flagged as quarantined (never silently dropped).

with unioned as (
    {% for model_name in var('customer_staging_models') %}
    select * from {{ ref(model_name) }}
    {% if not loop.last %}union all by name{% endif %}
    {% endfor %}
),

placeholders as (
    select value_type, value from {{ ref('placeholder_values') }}
),

standardized as (
    select
        u.source_system,
        u.source_record_id,
        u.source_system || ':' || coalesce(u.source_record_id,
            'MISSING-' || substr(md5(concat_ws('|', u._source_file, u.first_name, u.last_name, u.email_original, u.phone_original)), 1, 8)) as record_key,
        u.first_name,
        u.last_name,
        trim(coalesce(u.first_name, '') || ' ' || coalesce(u.last_name, '')) as full_name,
        case when u.email in (select value from placeholders where value_type = 'email') then null else u.email end as email,
        case when u.phone in (select value from placeholders where value_type = 'phone') then null else u.phone end as phone,
        u.date_of_birth,
        coalesce(c.city, {{ proper_case('u.city_raw') }})                     as city,
        u.source_updated_at,
        -- field-level problems: the row is kept, the bad value is blanked
        nullif(concat_ws(', ',
            case when u.email_original is not null and u.email is null then 'invalid_email' end,
            case when u.email in (select value from placeholders where value_type = 'email') then 'placeholder_email' end,
            case when u.phone_original is not null and u.phone is null then 'invalid_phone' end,
            case when u.phone in (select value from placeholders where value_type = 'phone') then 'placeholder_phone' end,
            case when u.dob_original is not null and u.date_of_birth is null then 'invalid_dob' end
        ), '')                                                                 as field_issues,
        u.email_original,
        u.phone_original,
        u._source_file,
        u._loaded_at
    from unioned u
    left join {{ ref('city_aliases') }} c
        on u.city_raw = c.city_alias
)

select
    *,
    -- row-level problems: the row cannot be used at all
    case
        when source_record_id is null then 'missing_source_id'
        when email is null and phone is null and full_name = '' then 'no_identifying_fields'
    end                         as quarantine_reason,
    quarantine_reason is not null as is_quarantined
from standardized
