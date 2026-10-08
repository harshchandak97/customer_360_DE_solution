-- CRM -> standard customer shape. One row per raw CRM row (nothing dropped here).
with source as (
    select * from {{ source('raw', 'crm_customers') }}
),

cleaned as (
    select
        'crm'                                                    as source_system,
        nullif(trim(crm_id), '')                                 as source_record_id,
        {{ proper_case('first_name') }}                          as first_name,
        {{ proper_case('last_name') }}                           as last_name,
        {{ clean_email('email') }}                               as email,
        {{ clean_phone('phone') }}                               as phone,
        {{ plausible_dob("try_strptime(date_of_birth, '%Y-%m-%d')::date") }} as date_of_birth,
        lower(trim(city))                                        as city_raw,
        try_cast(updated_at as timestamp)                        as source_updated_at,
        -- keep raw values that the checks below compare against
        nullif(trim(email), '')                                  as email_original,
        nullif(trim(phone), '')                                  as phone_original,
        nullif(trim(date_of_birth), '')                          as dob_original,
        _source_file,
        _loaded_at
    from source
)

select * from cleaned
