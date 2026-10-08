-- Online store -> standard customer shape. One row per raw store row (nothing dropped here).
with source as (
    select * from {{ source('raw', 'ecom_users') }}
),

names as (
    select
        *,
        -- drop titles like "Mr." / "Mrs." / "Dr."
        trim(regexp_replace(full_name, '^\s*(mr|mrs|ms|miss|dr)\.?\s+', '', 'i')) as name_no_title
    from source
),

split_names as (
    select
        *,
        case
            -- "SHARMA, Priya" -> last name first
            when name_no_title like '%,%' then trim(split_part(name_no_title, ',', 2))
            else split_part(trim(name_no_title), ' ', 1)
        end as first_name_raw,
        case
            when name_no_title like '%,%' then trim(split_part(name_no_title, ',', 1))
            -- everything after the first word
            else nullif(trim(substr(trim(name_no_title), length(split_part(trim(name_no_title), ' ', 1)) + 1)), '')
        end as last_name_raw
    from names
)

select
    'ecom'                                                       as source_system,
    nullif(trim(user_id), '')                                    as source_record_id,
    {{ proper_case('first_name_raw') }}                          as first_name,
    {{ proper_case('last_name_raw') }}                           as last_name,
    {{ clean_email('email_address') }}                           as email,
    {{ clean_phone('mobile') }}                                  as phone,
    {{ plausible_dob("try_strptime(dob, '%d/%m/%Y')::date") }}   as date_of_birth,
    lower(trim(city))                                            as city_raw,
    try_cast(last_updated as timestamp)                          as source_updated_at,
    nullif(trim(email_address), '')                              as email_original,
    nullif(trim(mobile), '')                                     as phone_original,
    nullif(trim(dob), '')                                        as dob_original,
    _source_file,
    _loaded_at
from split_names
