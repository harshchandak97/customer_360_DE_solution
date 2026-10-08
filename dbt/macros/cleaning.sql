{# Reusable cleaning rules, shared by every staging model. #}

{# Lowercase + trim. Returns NULL if the result does not look like an email. #}
{% macro clean_email(column) -%}
    case
        when regexp_full_match(lower(trim({{ column }})), '^[^@\s]+@[^@\s]+\.[^@\s]+$')
        then lower(trim({{ column }}))
    end
{%- endmacro %}

{# Keep digits only, then convert to +<country><10 digits>. Returns NULL if invalid.
   Handles 9845012345, 09845012345, 919845012345, +91 98450 12345, +91-98450-12345. #}
{% macro clean_phone(column) -%}
    case
        when length(regexp_replace({{ column }}, '[^0-9]', '', 'g')) = 10
            then '+{{ var("default_country_code") }}' || regexp_replace({{ column }}, '[^0-9]', '', 'g')
        when length(regexp_replace({{ column }}, '[^0-9]', '', 'g')) = 11
             and regexp_replace({{ column }}, '[^0-9]', '', 'g') like '0%'
            then '+{{ var("default_country_code") }}' || substr(regexp_replace({{ column }}, '[^0-9]', '', 'g'), 2)
        when length(regexp_replace({{ column }}, '[^0-9]', '', 'g')) = 12
             and regexp_replace({{ column }}, '[^0-9]', '', 'g') like '{{ var("default_country_code") }}%'
            then '+' || regexp_replace({{ column }}, '[^0-9]', '', 'g')
    end
{%- endmacro %}

{# "  rAHUL   verma " -> "Rahul Verma" #}
{% macro proper_case(column) -%}
    nullif(array_to_string(
        list_transform(
            list_filter(string_split(regexp_replace(lower(trim({{ column }})), '\s+', ' ', 'g'), ' '), w -> w <> ''),
            w -> upper(w[1]) || w[2:]
        ), ' '), '')
{%- endmacro %}

{# Birth dates outside 1900..today are treated as invalid. #}
{% macro plausible_dob(date_expr) -%}
    case when {{ date_expr }} between date '1900-01-01' and current_date then {{ date_expr }} end
{%- endmacro %}
