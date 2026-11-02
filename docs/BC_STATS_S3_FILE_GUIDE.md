# BC Stats Web Analytics: S3 File and Reporting-Month Guide

## Purpose

This document explains which files in the BC Stats web analytics S3 folder correspond to each reporting month. It is intended to help project contributors select the correct source files and avoid confusing the file-generation timestamp with the reporting period.

## S3 location

```text
s3://sp-ca-bc-gov-131565110619-12-microservices/client/webdata_bcstats/
```

The feed contains reports for three site groups:

- `outcomes_*`: Outcomes BC Stats
- `antiracism_*`: Anti-Racism website
- `govstats_*`: BC Stats pages and assets on `gov.bc.ca`

A complete monthly delivery normally contains 18 reports:

- 5 Outcomes reports
- 5 Anti-Racism reports
- 8 GovStats reports

## Quick reference

| Reporting month | Files to use | Generation or upload date | Notes |
|---|---|---:|---|
| May 2026 | `UAT_20260708/` | July 8, 2026 | Revised May dataset. Use this instead of `UAT/`. |
| June 2026 | Report-specific `v00_manual` files containing `20260729T` | July 29, 2026 | June data in the newer report-specific structure. `UAT_20260720/` is the earlier June UAT delivery. |
| July 2026 | Report-specific `v00_manual` files containing `20260910T22` | September 10, 2026 | Manual historical backfill requested by BC Stats. |
| August 2026 | Report-specific `v01_auto` files containing `20260910T01` or `20260910T02` | September 10, 2026 | Automated test run. Use these instead of the September 9 manual test files. |
| September 2026 | Report-specific `v01_auto` files generated on October 4, 2026 | Expected October 4, 2026 | First regular scheduled monthly run after setup. |
| Future months | Report-specific `v01_auto` files generated on the 4th of the following month | Monthly | The generation month is one month after the reporting month. |

> **Important:** The timestamp in a production-style filename records when the job generated the file. It does not directly identify the reporting month.

---

## File-selection details by reporting month

### May 2026

#### Use: revised May dataset

```text
s3://sp-ca-bc-gov-131565110619-12-microservices/client/webdata_bcstats/UAT_20260708/
```

This folder contains the revised May 2026 reports uploaded on July 8, 2026. The revisions included consistency and simplification changes to selected geolocation, asset, site-search, and Google-search reports.

Example:

```text
UAT_20260708/1_1_webdata_bcstats_outcomes_pageview_monthly_20260605_UAT.csv
```

#### Do not use: original May dataset

```text
s3://sp-ca-bc-gov-131565110619-12-microservices/client/webdata_bcstats/UAT/
```

The `UAT/` folder contains the original May reports generated on June 5 and 6, 2026. These files were superseded by the revised files in `UAT_20260708/`.

**May selection rule:**

```text
Use UAT_20260708/; do not ingest UAT/.
```

---

### June 2026

June appears in two structures.

#### Preferred for the current ingestion design: newer manual structure

```text
s3://sp-ca-bc-gov-131565110619-12-microservices/client/webdata_bcstats/{report_name}/v00_manual/*_20260729T*_part000.csv
```

Example:

```text
s3://sp-ca-bc-gov-131565110619-12-microservices/client/webdata_bcstats/govstats_search_monthly/v00_manual/webdata_bcstats_govstats_search_monthly_20260729T231855_part000.csv
```

These files were generated manually on July 29, 2026. Because they were generated before July had ended, and because they form the same complete 18-report set as the June UAT delivery, they are treated in this project as June 2026 data in the newer report-specific structure.

#### Earlier June UAT delivery

```text
s3://sp-ca-bc-gov-131565110619-12-microservices/client/webdata_bcstats/UAT_20260720/
```

This folder was explicitly delivered as the June UAT dataset. It uses the earlier consolidated UAT structure and was generated on July 20, 2026.

Example:

```text
UAT_20260720/3_7_webdata_bcstats_govstats_search_monthly_20260720_UAT.csv
```

The July 20 UAT files and July 29 manual files have different sizes, so they should not be combined within one monthly ingestion.

**June selection rule:**

```text
Use one complete June set only.
Current project convention: use the 20260729T files under the report-specific v00_manual folders.
Keep UAT_20260720/ as the earlier UAT reference copy.
```

> If the project has not formally chosen the July 29 files as authoritative, confirm this convention with the data provider before a production rebuild.

---

### July 2026

#### Use: manual July backfill

```text
s3://sp-ca-bc-gov-131565110619-12-microservices/client/webdata_bcstats/{report_name}/v00_manual/*_20260910T22*_part000.csv
```

Example:

```text
s3://sp-ca-bc-gov-131565110619-12-microservices/client/webdata_bcstats/govstats_search_monthly/v00_manual/webdata_bcstats_govstats_search_monthly_20260910T222909_part000.csv
```

The data provider manually generated this set on September 10, 2026 to fill the missing July reporting period. Although the filenames contain a September 10 generation timestamp, the files contain July 2026 data.

**July selection rule:**

```text
Use the 20260910T22 files under v00_manual.
Do not apply the normal "previous month" rule to this historical manual backfill.
```

---

### August 2026

August appears in both a manual test run and an automated test run.

#### Use: automated test run

```text
s3://sp-ca-bc-gov-131565110619-12-microservices/client/webdata_bcstats/{report_name}/v01_auto/*_20260910T01*_part000.csv
```

Some GovStats jobs completed shortly after 02:00, so the selection must also include:

```text
s3://sp-ca-bc-gov-131565110619-12-microservices/client/webdata_bcstats/{report_name}/v01_auto/*_20260910T02*_part000.csv
```

Examples:

```text
outcomes_pageview_monthly/v01_auto/webdata_bcstats_outcomes_pageview_monthly_20260910T013002_part000.csv
govstats_search_monthly/v01_auto/webdata_bcstats_govstats_search_monthly_20260910T020202_part000.csv
```

The data provider confirmed that this overnight automated test generated the August data under each report's `v01_auto` folder.

#### Do not use: preceding manual test run

```text
s3://sp-ca-bc-gov-131565110619-12-microservices/client/webdata_bcstats/{report_name}/v00_manual/*_20260909T16*_part000.csv
```

These files appear to be the manual test run that preceded the overnight automated run. For every report in the supplied S3 listing, the September 9 manual file has the same byte size as its corresponding September 10 `v01_auto` file. This strongly indicates that the two runs produced the same August dataset, although file size alone is not a cryptographic content check.

#### Additional September 10 manual files

```text
s3://sp-ca-bc-gov-131565110619-12-microservices/client/webdata_bcstats/{report_name}/v00_manual/*_20260910T08*_part000.csv
s3://sp-ca-bc-gov-131565110619-12-microservices/client/webdata_bcstats/{report_name}/v00_manual/*_20260910T09*_part000.csv
```

These files have the same byte sizes as the September 9 manual files and the September 10 automated files for the corresponding reports. They appear to be another manual rerun of the August dataset. They are not needed for the project ingestion because the confirmed August copy is under `v01_auto`.

**August selection rule:**

```text
Use the 20260910T01 and 20260910T02 files under v01_auto.
Do not ingest the 20260909T16 or 20260910T08/T09 files under v00_manual.
```

---

### September 2026 and later

Regular automated jobs are scheduled to run at midnight on the fourth day of each month. Files should be ready by the morning of the fourth. The delay allows up to three days for Google search data to become complete.

Expected location:

```text
s3://sp-ca-bc-gov-131565110619-12-microservices/client/webdata_bcstats/{report_name}/v01_auto/
```

Expected filename pattern:

```text
webdata_bcstats_{report_name}_monthly_YYYYMMDDTHHMMSS_part###.csv
```

Example for September 2026 data:

```text
outcomes_pageview_monthly/v01_auto/webdata_bcstats_outcomes_pageview_monthly_20261004THHMMSS_part000.csv
```

The file is generated on October 4, 2026, but contains complete September 2026 data.

#### Regular automated reporting-month rule

For scheduled `v01_auto` files:

```text
reporting month = calendar month immediately before the file-generation month
```

Examples:

| Generation date | Reporting month |
|---|---|
| October 4, 2026 | September 2026 |
| November 4, 2026 | October 2026 |
| December 4, 2026 | November 2026 |

This rule applies to regular automated deliveries. It must not be applied blindly to historical manual backfills.

---

## Meaning of folder versions

### `v00_manual`

The job was initiated manually. Manual files may represent:

- a historical backfill;
- a UAT or configuration test;
- a rerun of an existing reporting month; or
- a manual precursor to an automated job.

The reporting month cannot always be inferred from the generation timestamp. Use the documented month mapping and validate the reporting-period columns inside the CSV where possible.

### `v01_auto`

The file was generated by the automated job configuration. Beginning with the regular schedule, these reports run on the fourth day of each month and contain data for the previous completed month.

---

## Report folders

### Outcomes reports

```text
outcomes_pageview_monthly/
outcomes_click_monthly/
outcomes_referurl_monthly/
outcomes_platform_monthly/
outcomes_geoloc_monthly/
```

### Anti-Racism reports

```text
antiracism_pageview_monthly/
antiracism_click_monthly/
antiracism_referurl_monthly/
antiracism_platform_monthly/
antiracism_geoloc_monthly/
```

### GovStats reports

```text
govstats_pageview_monthly/
govstats_click_monthly/
govstats_referurl_monthly/
govstats_platform_monthly/
govstats_geoloc_monthly/
govstats_asset_monthly/
govstats_search_monthly/
govstats_google_monthly/
```

---

## Ingestion safeguards

1. **Do not use the filename timestamp as the reporting month without applying the documented mapping.** The timestamp records job execution time.
2. **Do not mix files from different runs for the same reporting month.** Select one complete 18-report set.
3. **Use all expected report folders.** A complete delivery contains 18 logical reports unless the provider communicates a change.
4. **Use every output part for a report.** Current files use `part000`, but future reports may produce `part001`, `part002`, and so on.
5. **Validate the month inside each CSV when a reporting-period field is available.** This is especially important for `v00_manual` backfills.
6. **Wait until the morning of the fourth for regular automated files.** There is no separate “drop complete” notification service.
7. **Do not treat identical file sizes as definitive proof of identical contents.** Use checksums or record-level comparison if exact duplication must be established.
8. **Archive ingested source files or record their S3 keys.** This provides reproducibility if additional manual or automated runs are later added to the same folders.

---

## Recommended ingestion manifest

The project should maintain a manifest containing at least:

```text
reporting_month
report_name
s3_key
generation_timestamp
run_type
file_size
checksum
retrieved_at
```

For historical files, the manifest should explicitly assign the reporting month rather than deriving it solely from the filename.

## Current authoritative mapping

```text
2026-05 -> UAT_20260708/
2026-06 -> {report_name}/v00_manual/*_20260729T*_part000.csv
2026-07 -> {report_name}/v00_manual/*_20260910T22*_part000.csv
2026-08 -> {report_name}/v01_auto/*_20260910T01*_part000.csv
           plus the GovStats v01_auto files generated at 20260910T02
2026-09 -> {report_name}/v01_auto/*_20261004T*_part###.csv
2026-10 onward -> {report_name}/v01_auto/, generated on the 4th of the following month
```

## Maintenance

Update this document when any of the following changes:

- month-specific S3 folders are introduced;
- the automated run schedule changes;
- report names or the expected report count change;
- the filename convention changes;
- the provider introduces a delivery-completion signal; or
- the project changes which historical June files are considered authoritative.
