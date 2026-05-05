DO $$
DECLARE
    v_recon_month varchar(6) := '202605';
    v_batch_run_id bigint := 1001;
    v_replace_month boolean := true;
    v_inserted_count bigint;
    v_updated_count bigint;
BEGIN
    CALL interfaces.sp_load_int_recon_mly_snapshot_counts(
        v_recon_month,
        v_batch_run_id,
        v_replace_month,
        v_inserted_count,
        v_updated_count
    );

    RAISE NOTICE 'Loaded month %, batch %, inserted %, updated %',
        v_recon_month, v_batch_run_id, v_inserted_count, v_updated_count;
END
$$;

-- Validation pack for that same month:
SELECT recon_month, count(*) AS row_count
FROM interfaces.int_recon_mly_snapshot
WHERE recon_month = '202605'
GROUP BY recon_month;

SELECT
    processing_status,
    created_by,
    updated_by,
    count(*) AS row_count
FROM interfaces.int_recon_mly_snapshot
WHERE recon_month = '202605'
GROUP BY processing_status, created_by, updated_by
ORDER BY row_count DESC;

SELECT
    recon_month,
    count(*) AS total_rows,
    round(100.0 * count(logical_id) / nullif(count(*), 0), 2) AS logical_id_pct,
    round(100.0 * count(claim_num) / nullif(count(*), 0), 2) AS claim_num_pct,
    round(100.0 * count(member_type) / nullif(count(*), 0), 2) AS member_type_pct,
    round(100.0 * count(payroll_office_number) / nullif(count(*), 0), 2) AS payroll_pct,
    round(100.0 * count(email) / nullif(count(*), 0), 2) AS email_pct,
    round(100.0 * count(phone_num) / nullif(count(*), 0), 2) AS phone_pct
FROM interfaces.int_recon_mly_snapshot
WHERE recon_month = '202605'
GROUP BY recon_month;

SELECT
    recon_month,
    appln_id,
    person_mbrsh_id,
    coalesce(plan_cd, '~') AS plan_cd,
    coalesce(cov_str_dt::text, '~') AS cov_str_dt,
    coalesce(cov_end_dt::text, '~') AS cov_end_dt,
    coalesce(claim_num, '~') AS claim_num,
    count(*) AS duplicate_count
FROM interfaces.int_recon_mly_snapshot
WHERE recon_month = '202605'
GROUP BY
    recon_month,
    appln_id,
    person_mbrsh_id,
    coalesce(plan_cd, '~'),
    coalesce(cov_str_dt::text, '~'),
    coalesce(cov_end_dt::text, '~'),
    coalesce(claim_num, '~')
HAVING count(*) > 1
ORDER BY duplicate_count DESC, appln_id, person_mbrsh_id
LIMIT 100;
```

If you want, I can also give a one-click DBeaver transaction wrapper that runs load + validations and auto-rolls back when inserted_count is below a threshold.