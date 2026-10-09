# 1. Questions and Assumptions

The objective is a consolidated customer dataset with a common customer identity, built from two
source systems whose data may contain duplicates, missing information, different formats,
conflicting information, and the same customer appearing in both systems.

## Questions I would ask if this were a real project

1. Who is the user of this data, and for what?
2. What are the latency requirements for this system?
3. What is the volume of data that we need to process?
4. Which is worse: a false merge (two people get one ID) or a false split (one person keeps two IDs)?
5. Which fields define a customer uniquely in both sources?
6. If two sources have conflicting customer information, which source should be given more importance?
7. Is there any shared ID across the systems (phone number, email ID, an identity card, etc.)?
8. Who resolves unclear cases? Is there a dataset of known correct matches to test the system against?

## Assumptions and their design implications

| # | Assumption | Answers question | Design implication |
|---|---|---|---|
| 1 | The analytics and marketing team is the user. They write SQL queries on top of this data. | 1 | Output is a set of SQL-queryable tables (Customer 360, crosswalk, match evidence), exported as CSV here |
| 2 | Data is refreshed daily, not in real time. | 2 | Batch architecture: a daily Airflow DAG; no streaming layer |
| 3 | Volume is a few MBs today and can grow to GBs/TBs. The implementation uses two CSVs of a few MBs. | 3 | Local DuckDB is enough here; the same dbt models move to a cloud warehouse (Snowflake) for scale. Blocking keeps matching from comparing every record with every other |
| 4 | A merge happens only on strong evidence. Uncertain pairs go to a human for review. | 4, 8 | Weighted scoring with a high auto-match threshold, a review queue for the middle band, and a check that fails the run if precision drops below 95% |
| 5 | No single field identifies a customer and there is no shared ID; identity is decided from email, phone, name, date of birth and city together. | 5, 7 | Rule-based matching across several fields, with a date-of-birth conflict as strong evidence against a merge |
| 6 | The CRM is more trustworthy for identity details (name, date of birth); the most recent record is best for contact details (email, phone, city). | 6 | Survivorship rules decide which value wins in the golden record; source ranking lives in a config file |
| 7 | No datasets were received, so I hand-built a small sample covering the five data issues in the brief, with a labelled answer key. | 8 | The pipeline reads whatever files the source config lists, so the real datasets can be dropped into `data/landing/` without code changes. The answer key drives an automated precision/recall check |
