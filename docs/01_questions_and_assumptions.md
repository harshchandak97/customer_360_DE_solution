# 1. Questions and Assumptions

Customer 360 comes down to two opposite mistakes:

- **False merge** - two different people get one ID (one customer could see another's orders: a privacy incident).
- **False split** - one person keeps two IDs (duplicate marketing, inflated customer counts).

Most questions below decide which mistake the business fears more and which data can be trusted.

| # | Question I would ask | Assumption made here | Design implication |
|---|---|---|---|
| 1 | Who uses the Customer 360 and for what? | Analytics and marketing, refreshed daily | Batch pipeline, no streaming layer |
| 2 | Which is worse: a false merge or a false split? | A false merge | Merge only on strong evidence; uncertain pairs go to a human review queue; run fails if precision < 95% |
| 3 | Is a "customer" a person, a household or a company? | An individual person | Family members sharing an email must not merge (date-of-birth conflict = negative evidence) |
| 4 | Which datasets, how big, how often, full or incremental? | No datasets were received, so a small hand-built sample of two sources (CRM, online store) covers every issue type in the brief | Pipeline reads whatever files `config/sources.yml` lists; real files can be dropped in without code changes |
| 5 | Is there a shared ID across systems (loyalty number, PAN)? | None | Matching relies on email, phone, name, date of birth and city |
| 6 | Is each source's record ID unique and stable? | Yes | `source_system:source_record_id` is the record key; rows without an ID are quarantined |
| 7 | Which source is more trustworthy for which field? | CRM for identity (name, DOB); most recent record for contact details | Survivorship rules + `seeds/source_trust.csv` |
| 8 | Are deletions sent, or do records just disappear? | Each delivery is a full snapshot | Raw tables are replaced per run; production would append with load timestamps and detect deletes |
| 9 | Which countries; do phones carry a country code? | India; numbers without a code get +91 | Phones normalised to `+91XXXXXXXXXX`; default country is a config value |
| 10 | Can emails or phones be shared or fake (family email, 9999999999)? | Yes | Placeholder values are blanked (`seeds/placeholder_values.csv`); a shared email alone cannot outweigh a DOB conflict |
| 11 | Are there known correct matches to test against? Who resolves unclear ones? | None provided; the sample ships with a labelled answer key; stewards in production | `data/expected/ground_truth.csv` drives a precision/recall check; review queue for stewards |
| 12 | Must the customer ID stay the same across runs? Can merges be undone? | Yes / yes | IDs derived deterministically from the group's records; production adds a persistent ID registry and merge history |
| 13 | Do we need history (what did we know last month)? | Yes in production; current state here | Production: snapshots (SCD Type 2) of the golden record |
| 14 | Which privacy laws apply; who may see raw PII? | All PII is restricted (GDPR / India DPDP Act style) | Production: column masking, role-based access, deletion via the crosswalk |
| 15 | Bad data: reject the whole file or set rows aside? | Set aside, stop only on structural failure | Bad fields blanked + warned; unusable rows quarantined; tests with error vs warn severity |

## Gaps in the brief
The brief does not define: whether "consolidated" means one merged record or linked records (I produce both: a golden record **and** a crosswalk), history, deletions, consent, freshness SLA, or who handles uncertain matches. These are documented above as assumptions.
