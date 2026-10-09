"""Run the whole pipeline locally without Docker/Airflow: load -> dbt build -> export.

Usage (from the project folder, virtual environment active):
    python run_pipeline.py
Airflow runs exactly the same three steps (airflow/dags/customer_360_pipeline.py).
"""
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DBT_DIR = ROOT / "dbt"
# dbt from the same virtual environment as this Python, else whatever "dbt" is on the PATH
_venv_dbt = Path(sys.executable).parent / "dbt"
DBT_BIN = str(_venv_dbt) if _venv_dbt.exists() else shutil.which("dbt")
if DBT_BIN is None:
    sys.exit("dbt not found. Activate the virtual environment and run: pip install -r requirements.txt")

env = {
    **os.environ,
    "DUCKDB_PATH": str(ROOT / "data" / "warehouse.duckdb"),
    "GROUND_TRUTH_PATH": str(ROOT / "data" / "expected" / "ground_truth.csv"),
}

STEPS = [
    ("1/3 Load raw files (bronze)", [sys.executable, "scripts/load_raw.py"], ROOT),
    ("2/3 Transform, match, test (dbt build)", [DBT_BIN, "build", "--profiles-dir", "."], DBT_DIR),
    ("3/3 Export outputs + run metrics", [sys.executable, "scripts/export_outputs.py"], ROOT),
]

for title, command, workdir in STEPS:
    print(f"\n=== {title} ===", flush=True)
    result = subprocess.run(command, cwd=workdir, env=env)
    if result.returncode != 0:
        sys.exit(f"Pipeline stopped: step '{title}' failed (exit code {result.returncode}).")

print("\nPipeline finished. Outputs are in the output/ folder.")
