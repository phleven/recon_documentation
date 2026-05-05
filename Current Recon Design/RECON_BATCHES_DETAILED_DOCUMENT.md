# Reconciliation Batches – Detailed Technical Documentation

**Project:** HBX Interface Batches  
**Module:** Outbound Trigger – Recon Batches  
**Date:** May 4, 2026  
**Package:** `com.deloitteinnovation.us.hbx.opm.batches.Outbound.trigger.reconBatches`

---

## Table of Contents

1. [Overview – All 4 Recon Batches](#1-overview--all-4-recon-batches)
2. [Batch 1 – Master Data Snapshot (INT-REC-MST-DATA-MLY-PRC)](#2-batch-1--master-data-snapshot-int-rec-mst-data-mly-prc)
3. [Batch 2 – Enrollment Recon Inbound (INT-ENRL-RECON-IN)](#3-batch-2--enrollment-recon-inbound-int-enrl-recon-in)
4. [Batch 3 – Snapshot Unmatched Reprocess (INT-SNAP-UNMATCH-REPROC)](#4-batch-3--snapshot-unmatched-reprocess-int-snap-unmatch-reproc)
5. [Batch 4 – Recon Outbound Monthly (INT-REC-OUT-MLY-PRC)](#5-batch-4--recon-outbound-monthly-int-rec-out-mly-prc)
6. [Cross-Batch Data Flow Diagram](#6-cross-batch-data-flow-diagram)
7. [Processing Status Reference](#7-processing-status-reference)
8. [Match Flag Reference (Outbound)](#8-match-flag-reference-outbound)
9. [Example Datasets and Scenarios](#9-example-datasets-and-scenarios)

---

## 1. Overview – All 4 Recon Batches

The reconciliation subsystem compares **HBX (PSHBS side)** enrollment data with **carrier (MENR/inbound file)** data to identify discrepancies and generate RCNO outbound files. The process flows through four sequential batches:

| # | Batch ID | Job Name | Description |
|---|----------|----------|-------------|
| 1 | `INT-REC-MST-DATA-MLY-PRC` | MasterDataBatch | Builds a monthly enrollment snapshot from HBX data |
| 2 | `INT-ENRL-RECON-IN` | EnrollmentReconInboundBatch | Matches carrier MENR records to snapshot |
| 3 | `INT-SNAP-UNMATCH-REPROC` | SnapshotUnmatchedReprocessBatch | Retries unmatched snapshots via logical_id |
| 4 | `INT-REC-OUT-MLY-PRC` | ReconOutboundMonthlyBatch | Produces RCNO outbound comparison rows |

**Job Parameters (common across all batches):**

| Parameter | Key | Description |
|-----------|-----|-------------|
| As-of date | `asOfDate` | Reference date for computing recon month |
| Recon month | `reconMonth` | Explicit override for recon period (format: `YYYY-MM-DD`) |
| Carrier name | `carrierName` | Optional filter for a specific carrier (used by Batch 1) |

**Recon Month Computation:**
- If `reconMonth` parameter is supplied → use it directly.
- Else if `asOfDate` is supplied → subtract 1 month from it.
- Else → subtract 1 month from today's date.
- Format returned: `yyyyMM` (e.g., `202503`) for Batches 2–4; `yyyy-MM-dd` for Batch 1.

---

## 2. Batch 1 – Master Data Snapshot (INT-REC-MST-DATA-MLY-PRC)

### 2.1 Purpose

Reads active HBX enrollment records and builds a **monthly snapshot** table (`interfaces.int_recon_mly_snapshot`) that serves as the authoritative HBX-side reference for reconciliation. Also writes an audit row per carrier snapshot run.

### 2.2 Components

| Role | Class |
|------|-------|
| Listener | `MasterDataListner` |
| Reader | JPA/SQL Reader (reads `MasterDataDto` from HBX `hbe`/`person_management` schemas) |
| Processor | `MasterDataProcessor` |
| Writer | `MasterDataWriter` |

### 2.3 Tables and Schemas

#### Source Tables (Read)

| Schema | Table / View | Purpose |
|--------|-------------|---------|
| `hbe` | `appln` | Application records |
| `hbe` | `plan_enrt` | Plan enrollment records |
| `hbe` | `plan_enrt_person_mbrsh_ac` | Enrollment ↔ person membership association |
| `hbe` | `reference_data` | Reference lookups (enrollment status, etc.) |
| `person_management` | `person_mbrsh` | Person membership |
| `person_management` | `person_mbrsh_person_name_ac` | Name association |
| `person_management` | `person_name` | Person name data |
| `person_management` | `person_mbrsh_person_aa_ac` | Additional attributes association |
| `person_management` | `person_addl_attr` | SSN, DOB, etc. |
| `person_management` | `person_organization_association` | Org/payroll code |
| `person_management` | `adr`, `person_adr`, `person_mbrsh_person_adr_ac` | Address data |
| `person_management` | `person_email` | Email |
| `person_management` | `person_mbrsh_person_phone_ac`, `person_phone` | Phone |
| `relationship` | `person_reln` | Relationship code |

#### Target Tables (Write)

| Schema | Table | Description |
|--------|-------|-------------|
| `interfaces` | `int_recon_mly_snapshot` | Monthly snapshot record per member+plan |
| `interfaces` | `int_recon_mly_snapshot_audit` | Audit log for each snapshot run |

### 2.4 Key Entity – `IntReconSnapshot` (`interfaces.int_recon_mly_snapshot`)

| Column | Type | Description |
|--------|------|-------------|
| `seq_num` (PK) | BIGINT | Auto-generated sequence |
| `recon_month` | VARCHAR(6) | Format: `yyyyMM` |
| `appln_id` | BIGINT | Application ID |
| `logical_id` | VARCHAR(15) | Logical application ID |
| `first_na` | VARCHAR(30) | First name |
| `last_na` | VARCHAR(30) | Last name |
| `middle_na` | VARCHAR(30) | Middle name |
| `birth_dt` | DATE | Date of birth |
| `subscr_ssn_num` | VARCHAR(9) | Subscriber SSN |
| `mbr_ssn_num` | VARCHAR(9) | Member SSN |
| `claim_num` | VARCHAR(50) | Claim/Annuitant number |
| `member_type` | VARCHAR(12) | Member type code |
| `plan_cd` | TEXT | Plan/enrollment code |
| `cov_str_dt` | DATE | Coverage start date |
| `cov_end_dt` | DATE | Coverage end date |
| `extnd_cov_end_dt` | DATE | Extended coverage end date |
| `matched_sw` | CHAR(1) | Match flag: `Y`/`N`/null |
| `mul_match_sw` | CHAR(1) | Multiple match flag: `Y`/`N`/null |
| `mapped_sw` | CHAR(1) | Mapped flag |
| `carrier_name` | VARCHAR(4) | Carrier identifier (e.g., `AETNA`, `BCBS`) |
| `person_mbrsh_id` | BIGINT | Person membership ID |
| `processing_status` | CHAR(1) | `P`=Pending, `I`=Identified, `O`=Obsolete, `F`=Failed |
| `subscr_id` | VARCHAR | Subscriber ID (populated after inbound match) |
| `mbr_id` | VARCHAR | Member ID (populated after inbound match) |
| `adr_str_1/2/3` | VARCHAR(64) | Mailing address lines |
| `city_na`, `state_cd`, `zip_code`, `ctry_cd` | VARCHAR | Address components |
| `home_adr_str_1/2/3`, `home_city_na`, etc. | VARCHAR | Home address |
| `phone_num` | BIGINT | Phone number |
| `email` | VARCHAR(1000) | Email address |
| `payroll_office_number` | VARCHAR | Payroll office number |
| `relationship_cd` | VARCHAR(2) | Relationship code |
| `sex_cd` | VARCHAR | Sex code |
| `is_primary` | CHAR(1) | Primary applicant flag |
| `batch_run_id` | BIGINT | Batch execution ID |
| `created_by`, `created_dt`, `updated_by`, `updated_dt` | — | Audit columns |

#### Audit Table – `interfaces.int_recon_mly_snapshot_audit`

| Column | Type | Description |
|--------|------|-------------|
| `seq_num` (PK) | BIGINT | Auto-generated |
| `carrier_name` | VARCHAR | Carrier |
| `snapshot_run_dt` | DATE | Date snapshot ran |
| `source` | VARCHAR | `BATCH-PARAM` (carrier passed as param) or `INBOUND-FILE` |
| `batch_run_id` | BIGINT | Batch run reference |
| `create_dt`, `created_by_nb`, `update_dt`, `updated_by_nb` | — | Audit |

### 2.5 Processing Logic

```
FOR EACH MasterDataDto (HBX enrollment record):
  1. Fetch person details (address, phone, email, SSN, etc.)
  2. Map DTO → IntReconSnapshot entity
  3. Generate dedup key: personMbrshId + "_" + planCd + "_" + reconMonth + "_" + covStrDt
  4. Check in-memory set: if key already seen → SKIP (duplicate in current run)
  5. Check DB: if record exists in int_recon_mly_snapshot for same key → SKIP
  6. Build IntReconSnapshotAudit entry
  7. SAVE snapshot + audit records
```

**Duplicate Prevention (two-tier):**
- **Tier 1 (In-memory):** `ConcurrentHashMap.newKeySet()` — static set cleared at job start, shared across partitions.
- **Tier 2 (Database):** Query `interfaces.int_recon_mly_snapshot` for existing record with same `person_mbrsh_id`, `plan_cd`, `recon_month`, `cov_str_dt`, `processing_status='P'`.

### 2.6 Key Stored Procedure / Function

```sql
-- Called by a Tasklet before the main step (loads pre-enrolled plan data)
SELECT interfaces.sp_preload_latest_enrolled_plan(:recon_date, :lookback_years);
-- lookback_years defaults to 7 (env var LOOKBACK_YEARS)
```

### 2.7 Sample Queries

**Snapshot lookup by SSN (used by Batch 2):**
```sql
SELECT * FROM interfaces.int_recon_mly_snapshot
WHERE mbr_ssn_num = ?
  AND recon_month = ?
  AND LOWER(carrier_name) = ?
  AND ((matched_sw IS NULL OR matched_sw = 'N') AND (mul_match_sw IS NULL OR mul_match_sw = 'N'))
  AND processing_status = 'P';
```

**Snapshot lookup by Claim ID:**
```sql
SELECT * FROM interfaces.int_recon_mly_snapshot
WHERE claim_num = ?
  AND recon_month = ?
  AND LOWER(carrier_name) = ?
  AND ((matched_sw IS NULL OR matched_sw = 'N') AND (mul_match_sw IS NULL OR mul_match_sw = 'N'))
  AND processing_status = 'P';
```

**Snapshot lookup by First Name, Last Name, DOB:**
```sql
SELECT * FROM interfaces.int_recon_mly_snapshot
WHERE LOWER(first_na) = ? AND LOWER(last_na) = ? AND birth_dt = ?
  AND recon_month = ?
  AND LOWER(carrier_name) = ?
  AND ((matched_sw IS NULL OR matched_sw = 'N') AND (mul_match_sw IS NULL OR mul_match_sw = 'N'))
  AND processing_status = 'P';
```

**Duplicate check before writing:**
```sql
SELECT CASE WHEN COUNT(*) > 0 THEN true ELSE false END
FROM interfaces.int_recon_mly_snapshot
WHERE person_mbrsh_id = ? AND plan_cd = ? AND recon_month = ? AND cov_str_dt = ? AND processing_status = 'P';
```

**Continuous enrollment chain (earliest cov start):**
```sql
WITH RECURSIVE continuous_enrollment AS (
  SELECT pepma.member_cov_start_dt, pepma.member_cov_end_dt, pe.enrt_cd
  FROM hbe.plan_enrt_person_mbrsh_ac pepma
  INNER JOIN hbe.plan_enrt pe ON pe.plan_enrt_id = pepma.plan_enrt_id
  WHERE pepma.person_mbrsh_id = ?1 AND pe.enrt_cd = ?2
    AND DATE(pepma.member_cov_start_dt) = DATE(?3)
    AND pepma.member_enrt_status_cd IN
      (SELECT reference_data_id FROM hbe.reference_data rd
       WHERE rd.effective_end_date IS NULL
         AND rd.reference_code IN ('ACT','DEN_INI','CNC','SUSP')
         AND rd.reference_type = 'EnrollmentStatus')
    AND pepma.effv_end_dt IS NULL
  UNION ALL
  SELECT pepma.member_cov_start_dt, pepma.member_cov_end_dt, pe.enrt_cd
  FROM hbe.plan_enrt_person_mbrsh_ac pepma
  INNER JOIN hbe.plan_enrt pe ON pe.plan_enrt_id = pepma.plan_enrt_id
  INNER JOIN continuous_enrollment ce ON pe.enrt_cd = ce.enrt_cd
    AND DATE(ce.member_cov_start_dt) = DATE(pepma.member_cov_end_dt) + INTERVAL '1 day'
  WHERE pepma.person_mbrsh_id = ?1
    AND pepma.member_enrt_status_cd IN (...)
    AND pepma.effv_end_dt IS NULL
)
SELECT MIN(member_cov_start_dt) FROM continuous_enrollment;
```

### 2.8 Status Flow

```
(HBX enrollment records)
        │
        ▼
  int_recon_mly_snapshot
        processing_status = 'P'  ← initial write
        matched_sw = null
        mul_match_sw = null
        │
        ▼ (after Batch 2 inbound match)
        processing_status = 'P'  (still, if matched; 'F' if error)
        matched_sw = 'Y'        ← exact match
        or mul_match_sw = 'Y'  ← multiple match
        │
        ▼ (after Batch 4 outbound)
        processing_status = 'I'  ← processed into RCNO outbound table
```

### 2.9 Validation Rules

| Rule | Description |
|------|-------------|
| Duplicate prevention | Skip if `personMbrshId + planCd + reconMonth + covStrDt` combination already exists in-memory or DB |
| Null check | If `value` is null, skip that item in the chunk |
| Audit source | `BATCH-PARAM` if `carrierName` parameter provided; `INBOUND-FILE` otherwise |

---

## 3. Batch 2 – Enrollment Recon Inbound (INT-ENRL-RECON-IN)

### 3.1 Purpose

Reads carrier-provided MENR (Monthly Enrollment) records from `interfaces.INT_RECON_MENR_IN_MLY_STG` and attempts to **match each MENR record to an HBX snapshot** record. Updates both tables with match results. A final tasklet marks records with coverage dates outside the recon month as `NM` (No Match / Mismatch).

### 3.2 Components

| Role | Class |
|------|-------|
| Listener | `EnrlnReconInboundBatchListner` |
| Reader | JPA Reader (keys: `EnrollmentReconInboundKey` — SSN + DOB unique pairs) |
| Processor | `EnrlnReconInboundBatchProcessor` |
| Writer | `EnrlnReconInboundBatchWriter` |
| Post-step Tasklet | `EnrlnReconMismatchTasklet` |

### 3.3 Tables and Schemas

#### Source / Working Table – `interfaces.INT_RECON_MENR_IN_MLY_STG`

| Column | Type | Description |
|--------|------|-------------|
| `SEQ_NUM` (PK) | BIGINT | Auto-generated |
| `SUBSCR_ID` | VARCHAR | Carrier subscriber ID |
| `MBR_ID` | VARCHAR | Carrier member ID |
| `MBR_RLSHP_CD` | VARCHAR | Member relationship code |
| `PAT_CD` | VARCHAR | Patient code |
| `LAST_NA` | VARCHAR | Last name |
| `FIRST_NA` | VARCHAR | First name |
| `MIDDLE_NA` | VARCHAR | Middle name |
| `BIRTH_DT` | DATE | Date of birth |
| `SEX_CD` | VARCHAR | Sex code |
| `MBR_SSN_NUM` | VARCHAR(9) | Member SSN |
| `SUBSCR_SSN_NUM` | VARCHAR(9) | Subscriber SSN |
| `PLAN_CD` | VARCHAR | Plan/enrollment code |
| `COV_START_DT` | DATE | Coverage start date |
| `COV_END_DT` | DATE | Coverage end date |
| `EXTN_COV_END_DT` | DATE | Extension coverage end date |
| `TERM_RSN_CD` | VARCHAR | Termination reason code |
| `ANNUITANT_NUM` | VARCHAR | Claim / Annuitant number |
| `PYRL_OFC_NUM` | VARCHAR | Payroll office number |
| `CARRIER_NAME` | VARCHAR | Carrier identifier |
| `PROCESSING_STATUS` | VARCHAR | `P`=Pending, `MI`=Match Identified, `S`=Success, `F`=Failed, `R`=Rejected, `NM`=No Match/Mismatch, `MM`=Mismatch |
| `mul_match_sw` | VARCHAR(1) | Multiple match flag |
| `snap_rec_seq_num` | BIGINT | FK to matched `int_recon_mly_snapshot.seq_num` |
| `APPLN_ID` | BIGINT | Application ID |
| `LOGICAL_ID` | VARCHAR | Logical application ID |
| `PERSON_MBRSH_ID` | VARCHAR | Person membership ID |
| `RECON_MONTH` | VARCHAR | Reconciliation month |
| `COMMENTS` | VARCHAR | Processing comments / rejection reason |
| `source_file_name` | VARCHAR | Source MENR file name |
| `CREATED_BY`, `CREATED_DT`, `UPDATED_BY`, `UPDATED_DT` | — | Audit |

#### Updated Tables (Write)

| Schema | Table | What is Updated |
|--------|-------|----------------|
| `interfaces` | `INT_RECON_MENR_IN_MLY_STG` | `processing_status`, `snap_rec_seq_num`, `mul_match_sw` |
| `interfaces` | `int_recon_mly_snapshot` | `subscr_id`, `mbr_id`, `matched_sw`, `mul_match_sw` |
| `hbe` | `plan_enrt` | `issuer_assigned_subscriber_id` (after exact match) |
| `hbe` | `plan_enrt_person_mbrsh_ac` | `issuer_assigned_member_id` (after exact match) |

### 3.4 Mandatory Field Validation

Before matching, each MENR record is validated for mandatory fields:

| Field | Column |
|-------|--------|
| `firstName` | `FIRST_NA` |
| `subscriberSsn` | `SUBSCR_SSN_NUM` |
| `birthDate` | `BIRTH_DT` |
| `coverageStartDt` | `COV_START_DT` |

If any field is missing → status set to `R` (Rejected), comment = `"Missing mandatory fields"`, and error logged.

### 3.5 Matching Logic Details

#### Step 1 – Reader Key Generation
The reader produces `EnrollmentReconInboundKey` objects (unique `SSN + DOB` pairs) for driving keys.

#### Step 2 – MENR Fetch per Key
```sql
SELECT * FROM interfaces.INT_RECON_MENR_IN_MLY_STG
WHERE COALESCE(NULLIF(TRIM(mbr_ssn_num), ''), '~') = COALESCE(NULLIF(TRIM(?1), ''), '~')
  AND birth_dt = ?2
  AND recon_month = ?3
  AND processing_status = 'P'
ORDER BY seq_num ASC;
```

#### Step 3 – Snapshot Lookup (3-tier fallback)
For each MENR record, snapshots are fetched using three progressive lookup strategies:

| Priority | Strategy | Condition |
|----------|----------|-----------|
| 1 | **By SSN** | `mbr_ssn_num = MENR.member_ssn AND recon_month = ? AND carrier_name = ?` |
| 2 | **By Claim ID** | Used if SSN lookup returns empty; `claim_num = MENR.claimId` |
| 3 | **By Name + DOB** | Used if Claim ID lookup returns empty; `first_na = ?, last_na = ?, birth_dt = ?` |

All lookups additionally filter: `processing_status = 'P'` AND `matched_sw IS NULL OR matched_sw = 'N'` AND `mul_match_sw IS NULL OR mul_match_sw = 'N'`.

Already-reserved snapshot IDs (matched to earlier MENR records in the same chunk) are excluded.

#### Step 4 – Multi-Stage Progressive Matching
Starting stage depends on which identifier is available on the MENR record:

| Starting Identifier | Initial Stage | Next Stage |
|--------------------|--------------|-----------|
| SSN present | SSN | CLAIM |
| No SSN, Claim ID present | CLAIM | DOB |
| Neither SSN nor Claim ID | DOB | PLAN |

**MatchStage enum (in order):**
```
SSN → CLAIM → DOB → PLAN → COVERAGE_START_DATE → COVERAGE_END_DATE
```

**At each stage:**
- Filter MENR candidates and snapshot candidates by the stage criterion.
- If either side becomes empty → **NO MATCH**.
- If both sides reduce to exactly 1 → **EXACT MATCH**.
- Continue to next stage if more than 1 on either side.
- After all stages, if snapshots > 1 → **MULTI-MATCH**.

**Stage filter logic:**

| Stage | MENR filter | Snapshot filter |
|-------|-------------|----------------|
| SSN | `candidate.memberSsn == item.memberSsn` | `candidate.mbrSSN == item.memberSsn` |
| CLAIM | `candidate.claimId == item.claimId` | `candidate.claimNum == item.claimId` |
| DOB | `firstName + lastName + birthDate` match | `firstNa + lastNa + birthDt` match |
| PLAN | `candidate.enrollmentCd == item.enrollmentCd` | `candidate.planCd == item.enrollmentCd` |
| COVERAGE_START_DATE | `candidate.coverageStartDt == item.coverageStartDt` | `candidate.covStrDt == item.coverageStartDt` |
| COVERAGE_END_DATE | `candidate.coverageEndDt == item.coverageEndDt` | `candidate.covEndDt == item.coverageEndDt` |

All `carrier_name` comparisons are case-insensitive across all stages.

String equality: both null/empty → match; one null and one not → no match; both present → case-insensitive trim comparison.

#### Step 5 – Match Resolution

**Exact Match (1:1):**
```
snapshot.subscr_id ← menr.subscriberId
snapshot.mbr_id    ← menr.memberId
snapshot.matched_sw = 'Y'
menr.processing_status = 'MI'  (Match Identified)
menr.snap_rec_seq_num = snapshot.seq_num
```

**Multi-Match (1:N snapshots):**
```
all matching snapshots: mul_match_sw = 'Y'
all matching snapshots: subscr_id ← menr.subscriberId
all matching snapshots: mbr_id ← menr.memberId
menr.snap_rec_seq_num = MAX(snapshot.seq_num)  (highest seq_num selected)
menr.mul_match_sw = 'Y'
menr.processing_status = 'MI'
```

**No Match:**
```
menr.snap_rec_seq_num = null
(status remains 'P')
```

### 3.6 Writer SQL Queries

```sql
-- Update MENR record
UPDATE interfaces.INT_RECON_MENR_IN_MLY_STG
SET processing_status = ?, snap_rec_seq_num = ?, mul_match_sw = ?,
    UPDATED_DT = ?, UPDATED_BY = ?
WHERE seq_num = ?;

-- Update Snapshot record
UPDATE interfaces.int_recon_mly_snapshot
SET subscr_id = ?, mbr_id = ?, matched_sw = ?, mul_match_sw = ?,
    UPDATED_DT = ?, UPDATED_BY = ?
WHERE seq_num = ?;

-- Update Subscriber ID on plan_enrt (if exact match)
UPDATE hbe.plan_enrt
SET issuer_assigned_subscriber_id = ?
WHERE plan_enrt_id IN (
  SELECT plan_enrt_id FROM hbe.plan_enrt_person_mbrsh_ac pepma
  INNER JOIN person_management.person_mbrsh pm ON pepma.person_mbrsh_id = pm.person_membership_id
  WHERE pepma.person_mbrsh_id = ? AND pm.is_primary_application_code = ?
);

-- Update Member ID on plan_enrt_person_mbrsh_ac (if exact match)
UPDATE hbe.plan_enrt_person_mbrsh_ac
SET issuer_assigned_member_id = ?
WHERE person_mbrsh_id = ?
  AND plan_enrt_id IN (SELECT plan_enrt_id FROM hbe.plan_enrt WHERE enrt_cd = ?);
```

### 3.7 Status Flow

```
MENR record arrives in INT_RECON_MENR_IN_MLY_STG
  processing_status = 'P'  (initial load)
         │
         ▼ (Batch 2 Processor)
  Mandatory fields check:
    FAIL  → processing_status = 'R' (Rejected)
    PASS  → continue matching
         │
         ▼ (Matching)
  EXACT MATCH  → processing_status = 'MI' (Match Identified)
                  mul_match_sw = null
  MULTI-MATCH  → processing_status = 'MI', mul_match_sw = 'Y'
  NO MATCH     → processing_status = 'P' (unchanged)
         │
         ▼ (Batch 4 Writer – after RCNO generation)
  Successfully processed → processing_status = 'S'
  Failed outbound       → processing_status = 'F'
```

---

## 4. Batch 3 – Snapshot Unmatched Reprocess (INT-SNAP-UNMATCH-REPROC)

### 4.1 Purpose

Reads snapshot records that remain unmatched (`matched_sw = 'N'` or null) and attempts a **secondary reconciliation pass** using `logical_id`. It fetches MENR records by `logical_id` with status `S` and tries to find an exact field-level match. Successfully matched snapshots are updated and corresponding MENR records are reset to `P` for re-entry into Batch 4.

### 4.2 Components

| Role | Class |
|------|-------|
| Listener | `SnapshotUnmatchedReprocessListener` |
| Reader | JPA Reader (reads `IntReconSnapshot` with unmatched criteria) |
| Processor | `SnapshotUnmatchedReprocessProcessor` |
| Writer | `SnapshotUnmatchedReprocessWriter` |

### 4.3 Source Query (Reader)

```sql
SELECT irms.*
FROM interfaces.int_recon_mly_snapshot irms
WHERE COALESCE(irms.matched_sw, 'N') = 'N'
  AND COALESCE(irms.mul_match_sw, 'N') = 'N'
  AND irms.processing_status = 'P';
```

### 4.4 Matching Logic

#### Step 1 – Fetch MENR by logical_id
```sql
SELECT * FROM interfaces.INT_RECON_MENR_IN_MLY_STG
WHERE logical_id = ?  -- snapshot.logical_id
  AND LOWER(carrier_name) = LOWER(?)  -- snapshot.carrier_name
  AND processing_status = 'S'         -- already successfully processed
ORDER BY seq_num DESC;
```

#### Step 2 – Exact Field Comparison
For each MENR candidate, compare all of the following (case-insensitive, null-safe):

| Field | Snapshot Column | MENR Column |
|-------|-----------------|-------------|
| Member SSN | `mbr_ssn_num` | `MBR_SSN_NUM` |
| Claim Number | `claim_num` | `ANNUITANT_NUM` |
| Plan Code | `plan_cd` | `PLAN_CD` |
| Coverage Start Date | `cov_str_dt` | `COV_START_DT` |
| Coverage End Date | `cov_end_dt` | `COV_END_DT` (null treated as `9999-12-31`) |

**All 5 criteria must match** for an exact match. Only the first matching MENR (DESC by seq_num) is taken.

#### Step 3 – Resolution

**Exact 1:1 Match:**
```
MENR: processing_status = 'P'  (reset for Batch 4 re-entry)
MENR: snap_rec_seq_num = snapshot.seq_num
Snapshot: matched_sw = 'Y', mul_match_sw = 'N'
Snapshot: subscr_id ← menr.subscriberId
Snapshot: mbr_id    ← menr.memberId
```

**No Match (or multiple):**
```
Processor returns null → Writer does not save → snapshot remains unmatched
```

### 4.5 Status Flow

```
int_recon_mly_snapshot (unmatched: matched_sw=N/null, processing_status=P)
        │
        ▼ (Batch 3 Processor)
  Fetch MENR by logical_id + status='S'
        │
        ▼
  Exact match (all 5 fields)?
    YES → snapshot: matched_sw='Y', mul_match_sw='N'
          MENR: processing_status='P' (re-queued for Batch 4)
    NO  → snapshot unchanged (still unmatched)
```

### 4.6 Validation Rules

| Rule | Detail |
|------|--------|
| Only exact 1:1 match accepted | No partial or multi-match in this batch |
| Null coverage end date | Treated as `9999-12-31` for comparison |
| Break on first match | Since MENR is ordered by `seq_num DESC`, first matching MENR (most recent) is used |

---

## 5. Batch 4 – Recon Outbound Monthly (INT-REC-OUT-MLY-PRC)

### 5.1 Purpose

Generates the **RCNO (Reconciliation Carrier Notification Outbound)** records by comparing matched MENR inbound data vs. HBX snapshot data field-by-field. Produces rows in `interfaces.int_recon_rcno_out_mly_stg` with individual match flags for every comparable field. Also handles unmatched HBX-side (PSHBS) records via a separate processor.

### 5.2 Components

| Role | Class |
|------|-------|
| Listener | `ReconOutMlyListeners` |
| Reader (MENR side) | JPA Reader (reads `IntReconEnrInMlyStg` with `processing_status = 'MI'` or `'P'`) |
| Processor (MENR side) | `ReconOutMlyProcessor` |
| Reader (PSHBS side) | JPA Reader (reads `MasterDataDto` from snapshot – unmatched records) |
| Processor (PSHBS side) | `ReconOutMlyPSHBSProcessor` |
| Writer | `ReconOutMlyWriter` |

### 5.3 Tables and Schemas

#### Target Table – `interfaces.int_recon_rcno_out_mly_stg`

Each row represents one RCNO comparison record with fields from both PSHBS (HBX snapshot) and MENR (carrier), plus match flags:

| Column | Type | Description |
|--------|------|-------------|
| `seq_num` (PK) | BIGINT | Auto-generated |
| `recon_month` | VARCHAR | Recon month |
| `original_menr_recon_month` | VARCHAR | Original MENR recon month |
| `snap_rec_seq_num` | BIGINT | FK to snapshot `seq_num` |
| `menr_rec_seq_num` | BIGINT | FK to MENR `seq_num` |
| `carrier_name` | VARCHAR | Carrier name |
| `appln_id` | BIGINT | Application ID |
| `logical_id` | VARCHAR | Logical application ID |
| `person_mbrsh_id` | VARCHAR | Person membership ID |
| `processing_status` | VARCHAR | `P`=Pending, `S`=Success, `F`=Failed |
| `subscr_id_match_flag` | VARCHAR | Subscriber ID match: `M`/`N`/`I`/`F` |
| `mbr_id_match_flag` | VARCHAR | Member ID match |

**PSHBS (HBX snapshot) columns:**

| Column | Source |
|--------|--------|
| `pshbs_subscr_id` | `snapshot.subscr_id` |
| `pshbs_mbr_id` | `snapshot.mbr_id` |
| `pshbs_annuitant_num` | `snapshot.claim_num` |
| `pshbs_last_na` | `snapshot.last_na` |
| `pshbs_first_na` | `snapshot.first_na` |
| `pshbs_dob` | `snapshot.birth_dt` |
| `pshbs_mem_ssn` | `snapshot.mbr_ssn_num` |
| `pshbs_subscr_ssn` | `snapshot.subscr_ssn_num` |
| `pshbs_pshb_plan_cd` | `snapshot.plan_cd` |
| `pshbs_enroll_cov_start_dt` | `snapshot.cov_str_dt` |
| `pshbs_enroll_cov_end_dt` | `snapshot.cov_end_dt` (default: `9999-12-31`) |
| `pshb_addr_ln1_nm`, `pshb_addr_ln2_nm`, `pshb_addr_ln3_nm` | Address lines |
| `pshb_city_nm`, `pshb_state_cd`, `pshb_zip_cd`, `pshb_cntry_cd` | Address |
| `pshb_phone_num` | Phone |
| `pshb_email` | Email |
| `pshb_pyrl_office_number` | Payroll office number |
| `pshb_reln_cd` | Relationship code |
| `pshb_extnd_cov_end_dt` | Extended coverage end date |
| `pshb_sex_cd` | Sex code |

**MENR (carrier) columns** mirror the above (`menr_subscr_id`, `menr_mbr_id`, `menr_annuitant_num`, etc.)

**Field-Level Match Flags** (per comparable field):

| Flag Column | Fields Compared |
|-------------|----------------|
| `annuitant_match_flag` | Annuitant/Claim number |
| `mem_ssn_match_flag` | Member SSN |
| `subscr_ssn_match_flag` | Subscriber SSN |
| `plan_cd_match_flag` | Plan code |
| `cov_start_dt_match_flag` | Coverage start date |
| `cov_end_dt_match_flag` | Coverage end date |
| `first_na_match_flag` | First name |
| `last_na_match_flag` | Last name |
| `dob_match_flag` | Date of birth |
| `addr_ln1_match_flag`, `addr_ln2_match_flag`, `addr_ln3_match_flag` | Address lines |
| `city_match_flag`, `state_match_flag`, `zip_match_flag`, `cntry_match_flag` | Address components |
| `phone_match_flag` | Phone |
| `email_match_flag` | Email |
| `pyrl_off_num_match_flag` | Payroll office number |
| `reln_cd_match_flag` | Relationship code |
| `extnd_cov_end_dt_match_flag` | Extended coverage end date |
| `sex_cd_match_flag` | Sex code |

**Record-Level Match Flags:**

| Flag Column | Meaning |
|-------------|---------|
| `subscr_id_match_flag` | Overall subscriber ID match: `M`=Matched, `N`=No MENR match, `I`=PSHBS unmatched, `F`=PSHBS unmatched with no match |
| `mbr_id_match_flag` | Overall member ID match |

#### Support Table – `interfaces.int_recon_rcno_enrl_cnt_mly_stg`

| Column | Description |
|--------|-------------|
| `recon_month` | Recon month |
| `pshb_plan_cd` | HBX plan code |
| `pshb_plan_cd_cnt` | Count of HBX records for that plan |
| `carrier_name` | Carrier |
| `carrier_plan_cd_cnt` | Count of carrier MENR records for that plan |
| `menr_file_prcss_dt` | MENR file process date |
| `processing_status` | Processing status |

### 5.4 Processing Logic – MENR Side (`ReconOutMlyProcessor`)

```
FOR EACH IntReconEnrInMlyStg (status MI or P):
  1. Call reconMlyOutboundService.processMenrPerson(menr, rcnoRecord)
     - Populate MENR fields: menrSubscrId, menrMbrId, menrAnnuitantNum, 
       menrLastNa, menrFirstNa, menrDob, menrMemSsn, menrSubscrSsn, 
       menrPshbPlanCd, menrEnrollCovStartDt, menrEnrollCovEndDt, 
       menrAddress, menrPhone, menrEmail, etc.
     - Populate PSHBS fields from matched snapshot
     - Set field-level match flags
  2. Set metadata: reconMonth, menrRecSeqNum, carrierName (uppercase), 
                   batchRunId, processingStatus = 'P'
  3. Return IntReconRcnoOutMlyStg
```

### 5.5 Processing Logic – PSHBS Side (`ReconOutMlyPSHBSProcessor`)

Handles HBX snapshot records that have NO matching MENR (i.e., HBX has the member but carrier does not):

```
FOR EACH MasterDataDto (unmatched snapshot):
  1. Populate PSHBS fields from snapshot
  2. Set MENR fields to null/empty
  3. reconMlyOutboundService.setMatchFlagFieldLevel(record, 'I')  -- PSHBS-only flag
  4. reconMlyOutboundService.setMatchFlagRecordLevel(record, 'F') -- no-match record flag
  5. Set snapRecSeqNum ← snapshot.seq_num
  6. processingStatus = 'P'
```

**Match Flags for PSHBS-unmatched:**
- `subscr_id_match_flag` = `'F'` (RECON_PSHBS_UNMATCHED_FLAG)
- Field-level flags = `'I'` (RECON_MENR_UNMATCHED_FLAG)

### 5.6 Writer Logic

```
1. Save all IntReconRcnoOutMlyStg records
2. If MENR step (reconOutMENRMlySlaveStep):
   UPDATE INT_RECON_MENR_IN_MLY_STG SET processing_status='S' 
   WHERE (processing_status='P' OR processing_status='MI') AND seq_num=?
   (skipped if subscr_id_match_flag = 'I')
3. If subscr_id_match_flag = 'F' (PSHBS unmatched):
   UPDATE interfaces.int_recon_mly_snapshot 
   SET processing_status='I' 
   WHERE recon_month=? AND seq_num=?
```

### 5.7 Status Flow

```
INT_RECON_MENR_IN_MLY_STG
  processing_status = 'MI' or 'P'
          │
          ▼ (Batch 4 Processor)
  RCNO record created in int_recon_rcno_out_mly_stg
  processing_status = 'P'
          │
          ▼ (Batch 4 Writer)
  MENR: processing_status = 'S'  (success)
  Snapshot: processing_status = 'I'  (identified/outbounded)
  RCNO: processing_status = 'P' → downstream processing
```

---

## 6. Cross-Batch Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                    HBX Application Database                          │
│  hbe.appln, hbe.plan_enrt, person_management.person_mbrsh, etc.     │
└────────────────────────┬────────────────────────────────────────────┘
                         │  READ
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│  BATCH 1: INT-REC-MST-DATA-MLY-PRC  (MasterDataBatch)               │
│  → WRITE: interfaces.int_recon_mly_snapshot  (processing_status='P')│
│  → WRITE: interfaces.int_recon_mly_snapshot_audit                   │
└────────────────────────┬────────────────────────────────────────────┘
                         │
         ┌───────────────┴─────────────────────┐
         │                                       │
         ▼                                       ▼
┌─────────────────────┐              ┌─────────────────────────────────┐
│  Carrier MENR File  │              │  int_recon_mly_snapshot (P)      │
│  → loaded into:     │              │  (HBX/PSHBS side reference)      │
│  INT_RECON_MENR_    │              └─────────────────────────────────┘
│  IN_MLY_STG (P)     │                           ▲
└──────────┬──────────┘                           │ LOOKUP
           │                                      │
           ▼                                      │
┌─────────────────────────────────────────────────────────────────────┐
│  BATCH 2: INT-ENRL-RECON-IN  (EnrollmentReconInboundBatch)           │
│  → MATCH MENR ↔ Snapshot                                            │
│  → UPDATE: MENR.processing_status = 'MI' / 'R' / 'P'               │
│  → UPDATE: snapshot.matched_sw = 'Y', mul_match_sw = 'Y'           │
│  → UPDATE: hbe.plan_enrt (subscr_id), plan_enrt_person_mbrsh_ac    │
│  → TASKLET: Mark outside-coverage MENR as 'NM'                     │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼  (unmatched snapshots still in 'P')
┌─────────────────────────────────────────────────────────────────────┐
│  BATCH 3: INT-SNAP-UNMATCH-REPROC  (SnapshotUnmatchedReprocess)      │
│  → READ: snapshots where matched_sw=N/null AND processing_status=P  │
│  → MATCH via logical_id + exact field comparison                    │
│  → UPDATE: snapshot.matched_sw='Y' (if found)                      │
│  → UPDATE: MENR.processing_status='P' (re-queue for Batch 4)        │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│  BATCH 4: INT-REC-OUT-MLY-PRC  (ReconOutboundMonthlyBatch)           │
│  STEP A (MENR side): READ MENR (MI/P) → field compare → RCNO row   │
│  STEP B (PSHBS side): READ unmatched snapshots → PSHBS-only RCNO   │
│  → WRITE: interfaces.int_recon_rcno_out_mly_stg                    │
│  → UPDATE: MENR.processing_status='S'                               │
│  → UPDATE: snapshot.processing_status='I'                           │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 7. Processing Status Reference

### `interfaces.int_recon_mly_snapshot` (processing_status)

| Status | Meaning |
|--------|---------|
| `P` | Pending – snapshot created, awaiting match |
| `I` | Identified – processed into RCNO outbound |
| `O` | Obsolete – superseded by newer snapshot |
| `F` | Failed – error during processing |

### `interfaces.INT_RECON_MENR_IN_MLY_STG` (processing_status)

| Status | Meaning |
|--------|---------|
| `P` | Pending – loaded, awaiting processing |
| `MI` | Match Identified – matched to a snapshot in Batch 2 |
| `S` | Success – successfully processed in Batch 4 |
| `R` | Rejected – failed mandatory field validation |
| `F` | Failed – processing error |

### `interfaces.int_recon_rcno_out_mly_stg` (processing_status)

| Status | Meaning |
|--------|---------|
| `P` | Pending – awaiting downstream processing |
| `S` | Success |
| `F` | Failed |

### `matched_sw` / `mul_match_sw` (snapshot)

| Flag | Value | Meaning |
|------|-------|---------|
| `matched_sw` | `Y` | Exactly matched to a MENR record |
| `matched_sw` | `N` / null | Not matched |
| `mul_match_sw` | `Y` | Multiple MENR records matched this snapshot |
| `mul_match_sw` | `N` / null | Not a multi-match |

---

## 8. Match Flag Reference (Outbound)

### Field-Level Flags (per compared field in `int_recon_rcno_out_mly_stg`)

| Flag Value | Meaning |
|------------|---------|
| `M` | Matched – values are equal |
| `N` | Not Matched – values differ |
| `I` | MENR-unmatched indicator (PSHBS record has no MENR counterpart) |

### Record-Level Flags (`subscr_id_match_flag`, `mbr_id_match_flag`)

| Flag Value | Constant | Scenario |
|------------|----------|---------|
| `M` | `RECON_MATCHED_FLAG` | Matched |
| `N` | `RECON_UNMATCHED_FLAG` | Carrier has member, HBX does not |
| `I` | `RECON_MENR_UNMATCHED_FLAG` | PSHBS-only: HBX has member, carrier does not |
| `F` | `RECON_PSHBS_UNMATCHED_FLAG` | PSHBS no-match record-level |

---


### 9.1 Key Views / Queries Used for Snapshot

**Snapshot candidates by logical_id:**
```sql
SELECT * FROM interfaces.int_recon_mly_snapshot
WHERE logical_id = ? AND recon_month = ? AND LOWER(carrier_name) = ?
  AND ((matched_sw IS NULL OR matched_sw = 'N') AND (mul_match_sw IS NULL OR mul_match_sw = 'N'))
  AND processing_status = 'P'
ORDER BY seq_num ASC;
```

**Snapshot candidates by plan + coverage start:**
```sql
SELECT * FROM interfaces.int_recon_mly_snapshot
WHERE plan_cd = ? AND cov_str_dt = ? AND recon_month = ?
  AND (matched_sw IS NULL OR matched_sw = 'N' OR mul_match_sw IS NULL OR mul_match_sw = 'N')
  AND processing_status = 'P';
```

**MENR file process date lookup:**
```sql
SELECT file_process_dt FROM interfaces.INT_RECON_MENR_IN_MLY_STG
WHERE processing_status = 'S' AND recon_month = ?
ORDER BY seq_num DESC LIMIT 1;
```

**Update snapshot status to Obsolete (before re-run):**
```sql
UPDATE interfaces.int_recon_mly_snapshot
SET processing_status = 'O'
WHERE recon_month = ? AND processing_status = ? AND carrier_name IN (?);
```

**Batch update MENR to Success:**
```sql
UPDATE interfaces.INT_RECON_MENR_IN_MLY_STG
SET processing_status = 'S', UPDATED_DT = ?, UPDATED_BY = ?
WHERE (processing_status = 'P' OR processing_status = 'MI') AND seq_num = ?;
```

**Batch update snapshot to Identified:**
```sql
UPDATE interfaces.int_recon_mly_snapshot
SET processing_status = 'I', UPDATED_DT = ?, UPDATED_BY = ?
WHERE recon_month = ? AND seq_num = ?;
```

---

*End of Document*

