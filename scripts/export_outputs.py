"""Export the final tables to output/ as CSV and record run metrics (monitoring).

- output/*.csv           : Customer 360 and supporting tables, ready to share
- quality.run_metrics    : one row per run (row counts, match outcomes, check results) kept as history
- output/run_summary.json: the latest run's metrics, readable at a glance
"""
import json
import os
from datetime import datetime, timezone
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = os.environ.get("DUCKDB_PATH", str(ROOT / "data" / "warehouse.duckdb"))
OUTPUT_DIR = ROOT / "output"

EXPORTS = {
    "customer_360": "select * from marts.customer_360 order by customer_id",
    "customer_xref": "select * from marts.customer_xref order by customer_id, record_key",
    "match_evidence": "select * from marts.match_evidence order by match_score desc",
    "review_queue": "select * from marts.review_queue",
    "quarantine_records": "select * from quality.quarantine_records",
    # latest run of every data quality check
    "dq_results": """
        select * from quality.dq_results
        where run_started_at = (select max(run_started_at) from quality.dq_results)
        order by status desc, check_name""",
}


def table_exists(con, schema: str, table: str) -> bool:
    return con.execute(
        "select count(*) from information_schema.tables where table_schema = ? and table_name = ?",
        [schema, table],
    ).fetchone()[0] > 0


def collect_metrics(con) -> dict:
    one = lambda sql: con.execute(sql).fetchone()[0]
    metrics = {
        "run_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S"),
        "source_rows": one("select count(*) from intermediate.int_customer_records"),
        "quarantined_rows": one("select count(*) from quality.quarantine_records"),
        "customers": one("select count(*) from marts.customer_360"),
        "customers_from_multiple_records": one(
            "select count(*) from marts.customer_360 where source_record_count > 1"),
        "largest_customer_record_count": one("select max(source_record_count) from marts.customer_360"),
        "pairs_compared": one("select count(*) from marts.match_evidence"),
        "pairs_auto_matched": one("select count(*) from marts.match_evidence where decision = 'match'"),
        "pairs_in_review": one("select count(*) from marts.review_queue"),
        "dq_checks_passed": one("""select count(*) from quality.dq_results where status = 'pass'
            and run_started_at = (select max(run_started_at) from quality.dq_results)"""),
        "dq_checks_warned": one("""select count(*) from quality.dq_results where status = 'warn'
            and run_started_at = (select max(run_started_at) from quality.dq_results)"""),
        "dq_checks_failed": one("""select count(*) from quality.dq_results where status in ('fail', 'error')
            and run_started_at = (select max(run_started_at) from quality.dq_results)"""),
    }
    if table_exists(con, "quality", "matching_accuracy"):
        precision, recall, recall_after_review = con.execute(
            "select precision, recall, recall_after_review from quality.matching_accuracy").fetchone()
        metrics.update(match_precision=float(precision), match_recall=float(recall),
                       match_recall_after_review=float(recall_after_review))
    return metrics


def main() -> None:
    OUTPUT_DIR.mkdir(exist_ok=True)
    con = duckdb.connect(DB_PATH)

    for name, query in EXPORTS.items():
        path = OUTPUT_DIR / f"{name}.csv"
        con.execute(f"copy ({query}) to '{path.as_posix()}' (header, delimiter ',')")
        print(f"Exported {path.relative_to(ROOT)}")
    if table_exists(con, "quality", "matching_accuracy"):
        path = OUTPUT_DIR / "matching_accuracy.csv"
        con.execute(f"copy (select * from quality.matching_accuracy) to '{path.as_posix()}' (header)")
        print(f"Exported {path.relative_to(ROOT)}")

    metrics = collect_metrics(con)
    # keep history of every run for monitoring trends
    con.execute("create table if not exists quality.run_metrics (run_at_utc timestamp, metrics json)")
    con.execute("insert into quality.run_metrics values (?, ?)", [metrics["run_at_utc"], json.dumps(metrics)])
    (OUTPUT_DIR / "run_summary.json").write_text(json.dumps(metrics, indent=2))
    con.close()

    print(json.dumps(metrics, indent=2))


if __name__ == "__main__":
    main()
