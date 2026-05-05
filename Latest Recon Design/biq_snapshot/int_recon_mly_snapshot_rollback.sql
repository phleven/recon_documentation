BEGIN;

-- Preview what will be removed
SELECT
    recon_month,
    batch_run_id,
    count(*) AS rows_to_delete
FROM interfaces.int_recon_mly_snapshot
WHERE recon_month = '202605'
  AND batch_run_id = 1001
GROUP BY recon_month, batch_run_id;

-- Actual rollback
DELETE FROM interfaces.int_recon_mly_snapshot
WHERE recon_month = '202605'
  AND batch_run_id = 1001;

-- Post-check
SELECT count(*) AS remaining_rows
FROM interfaces.int_recon_mly_snapshot
WHERE recon_month = '202605'
  AND batch_run_id = 1001;

COMMIT;
```

If you want a safer rollback:
~~~sql
ROLLBACK;