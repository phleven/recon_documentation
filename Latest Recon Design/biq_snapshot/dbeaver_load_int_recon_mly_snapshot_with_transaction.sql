BEGIN;

DO $$
DECLARE
    -- Run parameters
    v_recon_month varchar(6) := '202605';
    v_batch_run_id bigint := 1001;
    v_replace_month boolean := true;

    -- Safety thresholds
    v_min_inserted_rows bigint := 1000;
    v_min_logical_id_pct numeric := 99.00;
    v_min_claim_num_pct numeric := 10.00;
    v_min_member_type_pct numeric := 30.00;
    v_min_payroll_pct numeric := 30.00;
    v_min_email_pct numeric := 5.00;
    v_max_missing_logical_id bigint := 0;

    -- Outputs
    v_inserted_count bigint;
    v_updated_count bigint;

    -- Validation metrics
    v_total_rows bigint;
    v_logical_id_pct numeric;
    v_claim_num_pct numeric;
    v_member_type_pct numeric;
    v_payroll_pct numeric;
    v_email_pct numeric;
    v_missing_logical_id bigint;
BEGIN
    -- 1) Load
    CALL interfaces.sp_load_int_recon_mly_snapshot_counts(
        v_recon_month,
        v_batch_run_id,
        v_replace_month,
        v_inserted_count,
        v_updated_count
    );

    -- 2) Month-level validation metrics for this batch
    SELECT
        count(*) AS total_rows,
        round(100.0 * count(logical_id) / nullif(count(*), 0), 2) AS logical_id_pct,
        round(100.0 * count(claim_num) / nullif(count(*), 0), 2) AS claim_num_pct,
        round(100.0 * count(member_type) / nullif(count(*), 0), 2) AS member_type_pct,
        round(100.0 * count(payroll_office_number) / nullif(count(*), 0), 2) AS payroll_pct,
        round(100.0 * count(email) / nullif(count(*), 0), 2) AS email_pct,
        sum(CASE WHEN logical_id IS NULL THEN 1 ELSE 0 END) AS missing_logical_id
    INTO
        v_total_rows,
        v_logical_id_pct,
        v_claim_num_pct,
        v_member_type_pct,
        v_payroll_pct,
        v_email_pct,
        v_missing_logical_id
    FROM interfaces.int_recon_mly_snapshot
    WHERE recon_month = v_recon_month
      AND batch_run_id = v_batch_run_id;

    -- 3) Gate checks
    IF v_inserted_count < v_min_inserted_rows THEN
        RAISE EXCEPTION 'Load failed gate: inserted_count % < min %', v_inserted_count, v_min_inserted_rows;
    END IF;

    IF v_logical_id_pct < v_min_logical_id_pct THEN
        RAISE EXCEPTION 'Load failed gate: logical_id_pct % < min %', v_logical_id_pct, v_min_logical_id_pct;
    END IF;

    IF v_claim_num_pct < v_min_claim_num_pct THEN
        RAISE EXCEPTION 'Load failed gate: claim_num_pct % < min %', v_claim_num_pct, v_min_claim_num_pct;
    END IF;

    IF v_member_type_pct < v_min_member_type_pct THEN
        RAISE EXCEPTION 'Load failed gate: member_type_pct % < min %', v_member_type_pct, v_min_member_type_pct;
    END IF;

    IF v_payroll_pct < v_min_payroll_pct THEN
        RAISE EXCEPTION 'Load failed gate: payroll_pct % < min %', v_payroll_pct, v_min_payroll_pct;
    END IF;

    IF v_email_pct < v_min_email_pct THEN
        RAISE EXCEPTION 'Load failed gate: email_pct % < min %', v_email_pct, v_min_email_pct;
    END IF;

    IF v_missing_logical_id > v_max_missing_logical_id THEN
        RAISE EXCEPTION 'Load failed gate: missing_logical_id % > max %', v_missing_logical_id, v_max_missing_logical_id;
    END IF;

    -- 4) Success summary
    RAISE NOTICE 'Load OK: month=% batch=% inserted=% updated=% total=% logical_id_pct=% claim_num_pct=% member_type_pct=% payroll_pct=% email_pct=%',
        v_recon_month, v_batch_run_id, v_inserted_count, v_updated_count, v_total_rows,
        v_logical_id_pct, v_claim_num_pct, v_member_type_pct, v_payroll_pct, v_email_pct;
END
$$;

-- Optional post-run visibility
SELECT
    recon_month,
    batch_run_id,
    count(*) AS row_count
FROM interfaces.int_recon_mly_snapshot
WHERE recon_month = '202605'
  AND batch_run_id = 1001
GROUP BY recon_month, batch_run_id;

COMMIT;