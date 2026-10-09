"""Customer 360 pipeline: load raw files -> dbt build (clean, match, Customer 360, tests) -> export.

Runs once automatically when Airflow starts (latest daily interval), then daily.
The logic lives in the scripts and the dbt project; Airflow only runs the steps in order,
retries failures and keeps a history of every run.
"""
import os
from datetime import datetime, timedelta

from airflow.providers.standard.operators.bash import BashOperator
from airflow.sdk import DAG

# Paths inside the container (set in Dockerfile / docker-compose.yml)
PROJECT_DIR = os.environ.get("PIPELINE_PROJECT_DIR", "/opt/airflow/project")
PIPELINE_VENV = os.environ.get("PIPELINE_VENV", "/home/airflow/pipeline_venv")  # duckdb + dbt live here
PYTHON = f"{PIPELINE_VENV}/bin/python"
DBT = f"{PIPELINE_VENV}/bin/dbt"

with DAG(
    dag_id="customer_360_pipeline",
    description="Ingest two customer sources, reconcile identities, publish Customer 360",
    start_date=datetime(2026, 10, 1),
    schedule="@daily",
    catchup=False,                                   # only the latest day, not every day since start_date
    max_active_runs=1,                               # DuckDB allows one writer at a time
    default_args={"retries": 1, "retry_delay": timedelta(minutes=1)},
    tags=["customer_360"],
    doc_md=__doc__,
) as dag:

    load_raw = BashOperator(
        task_id="load_raw_files",
        bash_command=f"cd {PROJECT_DIR} && {PYTHON} scripts/load_raw.py",
    )

    dbt_build = BashOperator(
        task_id="dbt_build",
        doc_md="Seeds, models and data quality tests in dependency order. A failing test stops everything downstream.",
        bash_command=f"cd {PROJECT_DIR}/dbt && {DBT} build --profiles-dir .",
    )

    export_outputs = BashOperator(
        task_id="export_outputs",
        bash_command=f"cd {PROJECT_DIR} && {PYTHON} scripts/export_outputs.py",
    )

    load_raw >> dbt_build >> export_outputs
