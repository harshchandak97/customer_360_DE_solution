"""Load every source listed in config/sources.yml into DuckDB's raw schema, unchanged.

Bronze layer rules:
- keep every value exactly as received (all columns read as text)
- add metadata: which system, which file, when it was loaded
- safe to rerun: each run replaces the raw tables with the current files
"""
from datetime import datetime, timezone
from pathlib import Path

import duckdb
import yaml

ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = ROOT / "config" / "sources.yml"
DB_PATH = ROOT / "data" / "warehouse.duckdb"


def load_sources() -> None:
    sources = yaml.safe_load(CONFIG_PATH.read_text())["sources"]
    loaded_at = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")

    con = duckdb.connect(str(DB_PATH))
    con.execute("CREATE SCHEMA IF NOT EXISTS raw")

    for src in sources:
        csv_path = ROOT / src["file"]
        if not csv_path.exists():
            raise FileNotFoundError(f"Source '{src['name']}': file not found at {csv_path}")

        # all_varchar = keep everything as text, so nothing is changed on the way in
        # (e.g. phone 09900123456 would lose its leading zero if read as a number)
        con.execute(f"""
            CREATE OR REPLACE TABLE raw.{src['table']} AS
            SELECT
                *,
                '{src['name']}'          AS _source_system,
                '{csv_path.name}'        AS _source_file,
                TIMESTAMP '{loaded_at}'  AS _loaded_at
            FROM read_csv('{csv_path.as_posix()}', header = true, all_varchar = true)
        """)

        row_count = con.execute(f"SELECT count(*) FROM raw.{src['table']}").fetchone()[0]
        print(f"Loaded {row_count:>5} rows  {src['file']}  ->  raw.{src['table']}")

    con.close()


if __name__ == "__main__":
    load_sources()