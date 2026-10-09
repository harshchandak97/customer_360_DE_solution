# Airflow plus an isolated Python environment for the pipeline tools (duckdb, dbt).
# Keeping dbt in its own environment avoids version clashes with Airflow's own libraries.
FROM apache/airflow:3.2.2-python3.12

COPY requirements.txt /tmp/requirements.txt
RUN python -m venv /home/airflow/pipeline_venv \
 && /home/airflow/pipeline_venv/bin/pip install --no-cache-dir -r /tmp/requirements.txt
