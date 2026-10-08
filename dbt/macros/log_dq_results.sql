{# Runs after every dbt run/build (see on-run-end in dbt_project.yml).
   Appends one row per data quality check to quality.dq_results, so results are queryable
   and kept as history across runs. #}
{% macro log_dq_results(results) %}
    {% if execute %}
        {% do run_query("create schema if not exists quality") %}
        {% do run_query("
            create table if not exists quality.dq_results (
                run_started_at timestamp,
                check_name     varchar,
                check_type     varchar,
                checked_models varchar,
                severity       varchar,
                status         varchar,
                failing_rows   integer,
                message        varchar
            )") %}

        {% set rows = [] %}
        {% for res in results if res.node.resource_type == 'test' %}
            {% set check_type = res.node.test_metadata.name if res.node.test_metadata else 'custom' %}
            {% set models = res.node.depends_on.nodes | map('replace', 'model.customer_360.', '') | join(', ') %}
            {% set message = (res.message or '') | replace("'", "''") %}
            {% do rows.append(
                "(timestamp '" ~ run_started_at.strftime('%Y-%m-%d %H:%M:%S') ~ "', '"
                ~ res.node.name ~ "', '" ~ check_type ~ "', '" ~ models ~ "', '"
                ~ res.node.config.severity | lower ~ "', '" ~ res.status ~ "', "
                ~ (res.failures if res.failures is not none else 'null') ~ ", '" ~ message ~ "')"
            ) %}
        {% endfor %}

        {% if rows | length > 0 %}
            insert into quality.dq_results values {{ rows | join(', ') }}
        {% else %}
            select 1
        {% endif %}
    {% else %}
        select 1
    {% endif %}
{% endmacro %}
