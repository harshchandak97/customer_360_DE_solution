# Customer 360 - Data Engineering Solution

Two customer sources (a CRM and an online store) are ingested, cleaned into one standard shape,
matched into people, and published as a **Customer 360** with a unified `customer_id`, a crosswalk
back to every source record, the evidence behind every match decision, and automated data quality results.

**Stack:** DuckDB (warehouse) · dbt (transformations, matching, tests) · Apache Airflow 3 (orchestration) ·
Python (load and export) · Docker Compose (one-command run).

**Result on the sample data:** 14 source rows -> 1 quarantined -> 10 customers, 1 pair waiting for human review.
Matching precision **1.0**, recall **0.8** (1.0 once the pending review is approved). 35 data quality checks: 31 pass, 4 intended warnings, 0 failures.

| Document | Contents |
|---|---|
| [docs/01_questions_and_assumptions.md](docs/01_questions_and_assumptions.md) | Section 1: questions, assumptions and their design implications |
| [docs/02_architecture.md](docs/02_architecture.md) | Section 2: production vs assessment architecture diagrams, components, trade-offs |
| This README | How to run, implementation, identity reconciliation, data quality, extensibility, AI usage |

---

## How to run

### Option A: Docker Compose (recommended)
Requires Docker Desktop.

```bash
docker compose up --build
```

1. First build takes a few minutes.
2. Open **http://localhost:8080** (no login locally). The DAG `customer_360_pipeline` starts by itself;
   its three tasks turn green in about a minute: `load_raw_files -> dbt_build -> export_outputs`.
3. Results appear in `output/` on your machine.
4. Stop with `Ctrl+C`, then `docker compose down`.

### Option B: Without Docker
Requires Python 3.10-3.13.

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python run_pipeline.py
```

Runs the same three steps as the DAG and ends with `Pipeline finished`.

### Inspect the warehouse
```bash
duckdb -ui data/warehouse.duckdb      # browser UI; type .exit in the terminal when done
```
DuckDB allows one writer at a time: close the UI before running the pipeline again.

---

## What the pipeline does

| Step | Where | What happens |
|---|---|---|
| 1. Load (bronze) | `scripts/load_raw.py` | Every file listed in `config/sources.yml` is loaded into the `raw` schema unchanged (all columns as text, so e.g. phone leading zeros survive), plus `_source_system`, `_source_file`, `_loaded_at` |
| 2. Clean (silver) | `dbt/models/staging`, `int_customer_records` | One staging model per source maps it to the standard shape using shared macros (emails lowercased and validated, phones to `+91XXXXXXXXXX`, names split and title-cased, dates parsed, city aliases mapped). Bad **fields** are blanked and noted; unusable **rows** are quarantined |
| 3. Match | `int_candidate_pairs`, `int_scored_pairs` | Blocking picks pairs worth comparing; each pair is scored field by field; decision = match / review / no match |
| 4. Group | `int_customer_clusters` | Matched pairs are linked into people (connected components); each person gets a deterministic `customer_id` |
| 5. Customer 360 (gold) | `dbt/models/marts` | Golden record (survivorship), crosswalk, match evidence, review queue |
| 6. Quality | `dbt/tests`, `dbt/models/quality`, `log_dq_results` macro | Tests at every layer; results logged to `quality.dq_results`; accuracy vs the answer key |
| 7. Export + monitor | `scripts/export_outputs.py` | Writes `output/*.csv`, `output/run_summary.json`, and appends `quality.run_metrics` |
| Orchestration | `airflow/dags/customer_360_pipeline.py`, `docker-compose.yml` | Daily DAG, retries, one run at a time (DuckDB single writer) |

### Project structure
```
config/sources.yml          sources to load (add a source here)
data/landing/               input files            data/expected/   labelled answer key
scripts/                    load_raw.py, export_outputs.py
dbt/                        models (staging, intermediate, marts, quality), macros, seeds, tests
airflow/dags/               the DAG
output/                     Customer 360 and supporting outputs
docs/                       questions & assumptions, architecture
run_pipeline.py             same pipeline without Docker
Dockerfile, docker-compose.yml
```

### Data
No datasets were received, so `data/landing/` contains a small hand-built sample covering every issue
type named in the brief: duplicates within a source, missing values, different formats (names, emails,
phones, dates, city spellings), conflicting information (a customer who moved and changed email), the
same customer across systems, plus traps: a family-shared email, two different people with the same
common name, a dummy phone number, an invalid email and a row without an ID.
`data/expected/ground_truth.csv` records which rows are truly the same person.
Real files can be dropped into `data/landing/` without code changes (see Extensibility).

---

## Identity reconciliation (Section 4)

**Principle: precision first.** Wrongly merging two people is a privacy risk; missing a merge only
creates a duplicate. So the pipeline merges only on strong evidence and parks uncertain pairs for a human.

1. **Blocking** - only records sharing an email, a phone, or last name + city are compared
   (comparing everyone with everyone does not scale).
2. **Scoring** - points per field, from `dbt/seeds/match_rules.csv`:

   | Evidence | Points |
   |---|---|
   | Same email | +40 |
   | Same phone | +35 |
   | Same date of birth | +20 |
   | Similar name (Jaro-Winkler >= 0.90) | +15 |
   | Same city | +5 |
   | Different date of birth | **-40** |

3. **Decision** (thresholds in `dbt/dbt_project.yml`): score >= 70 **match**, 40-69 **review**, < 40 **no match**.
4. **Grouping** - matched pairs are linked transitively (A=B and B=C -> one person). Review pairs are not linked.
5. **Customer ID** - `C360-` + hash of the group's anchor record, so the same input gives the same ID every run.
6. **Survivorship** - identity fields (name, date of birth) from the most trusted source (`seeds/source_trust.csv`: CRM first),
   then most recent; contact fields (email, phone, city) from the most recent record. Empty values never win.

**Understanding the output**

| Question | Table / file |
|---|---|
| Which records were matched? | `customer_xref` - every source record -> its `customer_id` |
| Why were they matched (or not)? | `match_evidence` - every compared pair with score, decision and a readable reason |
| What is the unified customer? | `customer_360` - golden record, with `source_records`, `name_from_record`, `email_from_record` lineage |
| What is uncertain? | `review_queue` - pairs waiting for a data steward |

**Worked example.** CRM `C002` and `C003` (the same person entered twice) and store `U102` ("Rahul Varma", moved from Pune to Mumbai, new email):

| Pair | Score | Reason | Decision |
|---|---|---|---|
| C002 - C003 | 75 | phone +35, dob +20, name 1.0 +15, city +5 | match |
| C002 - U102 | 70 | phone +35, dob +20, name 0.944 +15 | match |

Result: one customer `C360-13C43B4C50` - Rahul **Verma** (name from the CRM), **rahul.verma@outlook.com** and **Mumbai** (most recent record).
By contrast, `C004`/`U103` share a family email but have different birth dates: score 5, no match.

---

## Data quality

| Layer | Checks | Severity |
|---|---|---|
| Staging | Source record IDs present | warn (missing IDs are quarantined) |
| Silver | Unique record keys; **no row lost or duplicated** between raw and silver; quarantine reasons valid; warnings for blanked invalid/placeholder values and for quarantined rows | error / warn |
| Matching | Unique pairs; no self-pairs; valid decisions; **no customer with two different birth dates**; warning for unusually large customers (over-merging) | error / warn |
| Gold | Unique `customer_id`; every crosswalk ID exists in Customer 360; every usable record has a customer; warning while reviews are pending | error / warn |
| Accuracy | **Fails the run if matching precision < 0.95** against the labelled answer key (switch off with `evaluate_accuracy: false` for data without an answer key) | error |

- A failing `error` test stops everything downstream of it (`dbt build`), so bad data does not reach the Customer 360.
- Every check's result is appended to `quality.dq_results` after each run (history), latest run exported to `output/dq_results.csv`.
- Run-level metrics (row counts, customers, pairs, review queue, check results, precision/recall) go to `quality.run_metrics` and `output/run_summary.json`.

**Current results:** 31 pass, 4 warnings, all intended (a row missing its ID, blanked invalid/placeholder values, the quarantined row, the pending review), 0 failures.

---

## Extensibility (Section 5)

| Change | What to do | Code change? |
|---|---|---|
| **New source** | 1) add an entry to `config/sources.yml`; 2) add one staging model mapping its columns to the standard shape (copy an existing one); 3) add its name to `customer_staging_models` in `dbt_project.yml` | One new SQL file; matching, Customer 360, tests and the DAG are untouched |
| **Tune matching** | Edit points in `seeds/match_rules.csv` or thresholds in `dbt_project.yml` | No |
| **New matching signal** (e.g. postcode) | Add one comparison in `int_scored_pairs.sql` and one row in `match_rules.csv` | One model |
| **New cleaning reference data** | Edit `seeds/city_aliases.csv`, `seeds/placeholder_values.csv`, `seeds/source_trust.csv` | No |
| **New data quality rule** | Add a test to a model's YAML, or a SQL file in `dbt/tests/` (choose `error` or `warn`) | No pipeline change; results are logged automatically |

## How it would scale
- **Volume:** blocking keeps comparisons near-linear; on Snowflake the same dbt models run unchanged (switch the dbt target). Large tables become incremental models.
- **Matching quality:** add more blocking keys; move to probabilistic matching (Splink / Zingg) when rules plateau; add steward decisions as must-link / cannot-link overrides.
- **Operations:** managed Airflow, Elementary for anomaly detection, alerting, CI running `dbt build` on every change.

## Limitations and what I would improve with more time
1. **Persistent ID registry** - IDs are deterministic, but a group's ID can change if its anchor record changes; production should keep IDs stable and log merges/splits.
2. **Steward workflow** - a small UI for the review queue whose decisions feed back as overrides.
3. **Incremental processing and history** - incremental models, snapshots (SCD Type 2) of the golden record.
4. **Phone parsing beyond India** - use `libphonenumber` with per-record country.
5. **Scale test** - a synthetic data generator (thousands of records with known duplicates) to tune thresholds.
6. **Security** - PII masking and role-based access (documented in the architecture, not implemented locally).
7. **CI/CD** - GitHub Actions running `dbt build` on every pull request.

---

## Where AI was used

**How I worked with AI:** I owned the problem framing, the architecture and the key decisions; I used an AI assistant
(Claude) as a pair engineer to generate code, explain unfamiliar tool details and speed up documentation.

| Area | My role | AI's role |
|---|---|---|
| Questions and assumptions | Wrote the questions and assumptions (e.g. precision-first: merge only on strong evidence, uncertain pairs to human review) | Helped structure them and link them to design implications |
| Architecture | Chose the stack (Snowflake + dbt + Airflow + Python for production, DuckDB locally), drew the diagram, set the design approach | Compared options and trade-offs on request |
| Implementation | Defined each pipeline step and its expected outcome, ran every step locally, checked outputs, debugged environment issues | Generated the code (loader, dbt models, macros, tests, DAG, Docker setup) one step at a time |
| Data | Designed the sample around the five data issues in the brief, with a labelled answer key | Helped draft the sample rows |
| Documentation | Reviewed and edited all docs | Drafted the README and docs |

**Where I challenged or changed the AI's output**
- **Scope:** under time pressure the AI suggested dropping dbt, Airflow and Docker; I kept the full designed stack and delivered it working end to end.
- **Production platform:** I questioned its initial Databricks recommendation; for an analytics team querying in SQL, a warehouse-first design (Snowflake or the client's existing warehouse) fits better.
- **Own framing over generated content:** I replaced AI-drafted questions, assumptions and diagrams with my own.
- **Prioritisation:** I deferred its proposed data generator to get a working end-to-end pipeline first.
- **Simplicity:** I pushed back on overly complex first drafts and reduced the architecture to its core components before adding detail.

**How I verified it:** ran each step and inspected the tables; an automated precision/recall check against the labelled
answer key (the run fails if precision < 95%); ran the full pipeline from a fresh clone and in Docker/Airflow.
