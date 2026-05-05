CREATE OR REPLACE PROCEDURE interfaces.sp_load_int_recon_mly_snapshot_counts(
    IN  p_recon_month varchar(6),
    IN  p_batch_run_id bigint,
    IN  p_replace_month boolean DEFAULT true,
    OUT o_inserted_count bigint,
    OUT o_updated_count bigint
)
LANGUAGE plpgsql
AS $procedure$
BEGIN
    o_inserted_count := 0;
    o_updated_count := 0;

    IF p_replace_month THEN
        DELETE FROM interfaces.int_recon_mly_snapshot
        WHERE recon_month = p_recon_month;
    END IF;

    WITH params AS (
        SELECT
            p_recon_month::varchar(6) AS recon_month,
            to_date(p_recon_month || '01', 'YYYYMMDD') AS month_start,
            (to_date(p_recon_month || '01', 'YYYYMMDD') + interval '1 month - 1 day')::date AS month_end,
            p_batch_run_id::bigint AS batch_run_id
    ),
    latest_plan AS (
        SELECT *
        FROM (
            SELECT
                pepma.person_mbrsh_id,
                pe.enrt_cd AS plan_cd,
                pepma.member_cov_start_dt::date AS cov_str_dt,
                pepma.member_cov_end_dt::date AS cov_end_dt,
                pe.issuer_assigned_subscriber_id AS subscr_id,
                pepma.issuer_assigned_member_id AS mbr_id,
                isu.atoz AS carrier_name,
                row_number() OVER (
                    PARTITION BY pepma.person_mbrsh_id
                    ORDER BY
                        coalesce(pepma.member_cov_end_dt, date '2999-12-31') DESC,
                        pepma.member_cov_start_dt DESC,
                        pe.plan_enrt_id DESC
                ) AS rn
            FROM hbe.plan_enrt_person_mbrsh_ac pepma
            JOIN hbe.plan_enrt pe
              ON pe.plan_enrt_id = pepma.plan_enrt_id
            JOIN hbe.plan_variant pv
              ON pv.planenrollmentcode = pe.enrt_cd
             AND pv.hpf_plan_id = pe.hpf_plan_id
            JOIN hbe.hpf_plan hp
              ON hp.hpf_plan_id = pv.hpf_plan_id
            JOIN hbe.issuer isu
              ON isu.issuer_id = hp.issuer_id
            CROSS JOIN params p
            WHERE pepma.effv_end_dt IS NULL
              AND pe.effv_end_dt IS NULL
              AND coalesce(pepma.member_cov_end_dt::date, p.month_end) >= p.month_start
              AND pepma.member_cov_start_dt::date <= p.month_end
        ) s
        WHERE rn = 1
    ),
    latest_name AS (
        SELECT *
        FROM (
            SELECT
                ac.person_membership_id,
                pn.first_name AS first_na,
                pn.middle_name AS middle_na,
                pn.last_name AS last_na,
                row_number() OVER (
                    PARTITION BY ac.person_membership_id
                    ORDER BY
                        coalesce(ac.effective_end_date, date '2999-12-31') DESC,
                        ac.effective_start_date DESC,
                        pn.update_datetime DESC NULLS LAST,
                        pn.create_datetime DESC NULLS LAST
                ) AS rn
            FROM person_management.person_mbrsh_person_name_ac ac
            JOIN person_management.person_name pn
              ON pn.person_name_id = ac.person_name_id
            WHERE ac.effective_end_date IS NULL
              AND pn.effective_end_date IS NULL
        ) s
        WHERE rn = 1
    ),
    latest_phone AS (
        SELECT *
        FROM (
            SELECT
                ac.person_membership_id,
                pp.phone_number::numeric AS phone_num,
                row_number() OVER (
                    PARTITION BY ac.person_membership_id
                    ORDER BY
                        CASE WHEN rd.reference_code = 'YES' THEN 0 ELSE 1 END,
                        coalesce(ac.effective_end_date, date '2999-12-31') DESC,
                        ac.effective_start_date DESC,
                        pp.update_datetime DESC NULLS LAST
                ) AS rn
            FROM person_management.person_mbrsh_person_phone_ac ac
            JOIN person_management.person_phone pp
              ON pp.person_phone_id = ac.person_phone_id
            LEFT JOIN hbe.reference_data rd
              ON rd.reference_data_id = pp.is_primary_phone_number_code
            WHERE ac.effective_end_date IS NULL
              AND pp.effective_end_date IS NULL
        ) s
        WHERE rn = 1
    ),
    latest_email AS (
        SELECT *
        FROM (
            SELECT
                pe.person_membership_id,
                pe.email,
                row_number() OVER (
                    PARTITION BY pe.person_membership_id
                    ORDER BY
                        CASE WHEN rd.reference_code = 'YES' THEN 0 ELSE 1 END,
                        coalesce(pe.effective_end_date, date '2999-12-31') DESC,
                        pe.effective_start_date DESC,
                        pe.update_datetime DESC NULLS LAST
                ) AS rn
            FROM person_management.person_email pe
            LEFT JOIN hbe.reference_data rd
              ON rd.reference_data_id = pe.is_primary_email_code
            WHERE pe.effective_end_date IS NULL
        ) s
        WHERE rn = 1
    ),
    mail_addr AS (
        SELECT *
        FROM (
            SELECT
                ac.person_membership_id,
                a.line1_address AS adr_str_1,
                a.line2_address AS adr_str_2,
                a.line3_address AS adr_str_3,
                a.city AS city_na,
                a.state_code AS state_cd,
                a.zip_code AS zip_code,
                a.country_code AS ctry_cd,
                row_number() OVER (
                    PARTITION BY ac.person_membership_id
                    ORDER BY
                        CASE WHEN rd.reference_code = 'YES' THEN 0 ELSE 1 END,
                        coalesce(ac.effective_end_date, date '2999-12-31') DESC,
                        ac.effective_start_date DESC
                ) AS rn
            FROM person_management.person_mbrsh_person_adr_ac ac
            JOIN person_management.person_adr pa
              ON pa.person_address_id = ac.person_address_id
            JOIN person_management.adr a
              ON a.address_id = pa.address_id
            LEFT JOIN hbe.reference_data rd
              ON rd.reference_data_id = pa.is_mailing_address_code
            WHERE ac.effective_end_date IS NULL
              AND pa.effective_end_date IS NULL
        ) s
        WHERE rn = 1
    ),
    home_addr AS (
        SELECT *
        FROM (
            SELECT
                ac.person_membership_id,
                a.line1_address AS home_adr_str_1,
                a.line2_address AS home_adr_str_2,
                a.line3_address AS home_adr_str_3,
                a.city AS home_city_na,
                a.state_code AS home_state_cd,
                a.zip_code AS home_zip_code,
                a.country_code AS home_ctry_cd,
                row_number() OVER (
                    PARTITION BY ac.person_membership_id
                    ORDER BY
                        CASE WHEN rd.reference_code = 'NO' OR rd.reference_code IS NULL THEN 0 ELSE 1 END,
                        coalesce(ac.effective_end_date, date '2999-12-31') DESC,
                        ac.effective_start_date DESC
                ) AS rn
            FROM person_management.person_mbrsh_person_adr_ac ac
            JOIN person_management.person_adr pa
              ON pa.person_address_id = ac.person_address_id
            JOIN person_management.adr a
              ON a.address_id = pa.address_id
            LEFT JOIN hbe.reference_data rd
              ON rd.reference_data_id = pa.is_mailing_address_code
            WHERE ac.effective_end_date IS NULL
              AND pa.effective_end_date IS NULL
        ) s
        WHERE rn = 1
    ),
    latest_addl_attr AS (
        SELECT *
        FROM (
            SELECT
                ac.person_membership_id,
                paa.birth_date::date AS birth_dt,
                paa.gender_code AS sex_cd,
                paa.ssn_tx AS mbr_ssn_num,
                paa.csa_csf_num AS claim_num,
                row_number() OVER (
                    PARTITION BY ac.person_membership_id
                    ORDER BY
                        coalesce(ac.effective_end_date, date '2999-12-31') DESC,
                        ac.effective_start_date DESC,
                        paa.update_datetime DESC NULLS LAST,
                        paa.create_datetime DESC NULLS LAST
                ) AS rn
            FROM person_management.person_mbrsh_person_aa_ac ac
            JOIN person_management.person_addl_attr paa
              ON paa.person_additional_attribute_id = ac.person_additional_attribute_id
            WHERE ac.effective_end_date IS NULL
              AND paa.effective_end_date IS NULL
        ) s
        WHERE rn = 1
    ),
    latest_employment AS (
        SELECT *
        FROM (
            SELECT
                pe.person_mbrsh_id AS person_membership_id,
                rd_member.reference_code AS member_type,
                pe.payroll_office_number::varchar AS payroll_office_number,
                row_number() OVER (
                    PARTITION BY pe.person_mbrsh_id
                    ORDER BY pe.updtd_dt DESC NULLS LAST, pe.crtd_dt DESC NULLS LAST, pe.person_employment_id DESC
                ) AS rn
            FROM hbe.person_employment pe
            LEFT JOIN hbe.reference_data rd_member
              ON rd_member.reference_data_id = pe.member_type
        ) s
        WHERE rn = 1
    ),
    primary_subscriber_ssn AS (
        SELECT *
        FROM (
            SELECT
                pm.application_id,
                paa.ssn_tx AS subscr_ssn_num,
                row_number() OVER (PARTITION BY pm.application_id ORDER BY pm.person_membership_id) AS rn
            FROM person_management.person_mbrsh pm
            JOIN hbe.reference_data rd_yes
              ON rd_yes.reference_data_id = pm.is_primary_application_code
             AND rd_yes.reference_code = 'YES'
            JOIN person_management.person_mbrsh_person_aa_ac ac
              ON ac.person_membership_id = pm.person_membership_id
             AND ac.effective_end_date IS NULL
            JOIN person_management.person_addl_attr paa
              ON paa.person_additional_attribute_id = ac.person_additional_attribute_id
             AND paa.effective_end_date IS NULL
            WHERE pm.effective_end_date IS NULL
        ) s
        WHERE rn = 1
    ),
    base_rows AS (
        SELECT
            p.recon_month,
            pm.application_id AS appln_id,
            NULL::varchar AS logical_id,
            lp.subscr_id,
            lp.mbr_id,
            ln.first_na,
            coalesce(ln.middle_na, '') AS middle_na,
            ln.last_na,
            la.birth_dt,
            pss.subscr_ssn_num,
            la.claim_num,
            le.member_type,
            lp.plan_cd,
            NULL::varchar AS matched_sw,
            NULL::varchar AS mapped_sw,
            NULL::varchar AS mul_match_sw,
            NULL::varchar AS comments,
            current_date AS crtd_dt,
            lp.cov_str_dt,
            lp.cov_end_dt,
            ph.phone_num,
            em.email,
            ma.adr_str_1,
            ma.adr_str_2,
            ma.adr_str_3,
            ma.city_na,
            ma.state_cd,
            ma.zip_code,
            ma.ctry_cd,
            CASE rd_prim.reference_code WHEN 'YES' THEN 'Y' WHEN 'NO' THEN 'N' ELSE NULL END AS is_primary,
            pm.person_membership_id::numeric AS person_mbrsh_id,
            'P'::varchar AS processing_status,
            lp.carrier_name,
            la.mbr_ssn_num,
            p.batch_run_id,
            NULL::varchar AS error_cd,
            'INT-REC-MST-DATA-MLY-PRC'::varchar AS created_by,
            now() AS created_dt,
            'INT-REC-MST-DATA-MLY-PRC'::varchar AS updated_by,
            now() AS updated_dt,
            le.payroll_office_number,
            CASE WHEN rd_prim.reference_code = 'YES' THEN '18' ELSE NULL END AS relationship_cd,
            NULL::date AS extnd_cov_end_dt,
            la.sex_cd,
            ha.home_adr_str_1,
            ha.home_adr_str_2,
            ha.home_adr_str_3,
            ha.home_city_na,
            ha.home_state_cd,
            ha.home_zip_code,
            ha.home_ctry_cd
        FROM params p
        JOIN person_management.person_mbrsh pm
          ON pm.effective_end_date IS NULL
        JOIN latest_plan lp
          ON lp.person_mbrsh_id = pm.person_membership_id
        LEFT JOIN latest_name ln
          ON ln.person_membership_id = pm.person_membership_id
        LEFT JOIN latest_phone ph
          ON ph.person_membership_id = pm.person_membership_id
        LEFT JOIN latest_email em
          ON em.person_membership_id = pm.person_membership_id
        LEFT JOIN mail_addr ma
          ON ma.person_membership_id = pm.person_membership_id
        LEFT JOIN home_addr ha
          ON ha.person_membership_id = pm.person_membership_id
        LEFT JOIN latest_addl_attr la
          ON la.person_membership_id = pm.person_membership_id
        LEFT JOIN latest_employment le
          ON le.person_membership_id = pm.person_membership_id
        LEFT JOIN hbe.reference_data rd_prim
          ON rd_prim.reference_data_id = pm.is_primary_application_code
        LEFT JOIN primary_subscriber_ssn pss
          ON pss.application_id = pm.application_id
    )
    INSERT INTO interfaces.int_recon_mly_snapshot (
        recon_month, appln_id, logical_id, subscr_id, mbr_id,
        first_na, middle_na, last_na, birth_dt, subscr_ssn_num,
        claim_num, member_type, plan_cd, matched_sw, mapped_sw, mul_match_sw, comments,
        crtd_dt, cov_str_dt, cov_end_dt, phone_num, email,
        adr_str_1, adr_str_2, adr_str_3, city_na, state_cd, zip_code, ctry_cd,
        is_primary, person_mbrsh_id, processing_status, carrier_name, mbr_ssn_num,
        batch_run_id, error_cd, created_by, created_dt, updated_by, updated_dt,
        payroll_office_number, relationship_cd, extnd_cov_end_dt, sex_cd,
        home_adr_str_1, home_adr_str_2, home_adr_str_3, home_city_na, home_state_cd, home_zip_code, home_ctry_cd
    )
    SELECT
        recon_month, appln_id, logical_id, subscr_id, mbr_id,
        first_na, middle_na, last_na, birth_dt, subscr_ssn_num,
        claim_num, member_type, plan_cd, matched_sw, mapped_sw, mul_match_sw, comments,
        crtd_dt, cov_str_dt, cov_end_dt, phone_num, email,
        adr_str_1, adr_str_2, adr_str_3, city_na, state_cd, zip_code, ctry_cd,
        is_primary, person_mbrsh_id, processing_status, carrier_name, mbr_ssn_num,
        batch_run_id, error_cd, created_by, created_dt, updated_by, updated_dt,
        payroll_office_number, relationship_cd, extnd_cov_end_dt, sex_cd,
        home_adr_str_1, home_adr_str_2, home_adr_str_3, home_city_na, home_state_cd, home_zip_code, home_ctry_cd
    FROM base_rows;

    GET DIAGNOSTICS o_inserted_count = ROW_COUNT;

    WITH latest_menr AS (
        SELECT *
        FROM (
            SELECT
                s.recon_month,
                s.appln_id,
                s.person_mbrsh_id::numeric AS person_mbrsh_id,
                s.logical_id,
                s.subscr_id,
                s.mbr_id,
                s.mbr_rlshp_cd AS relationship_cd,
                s.mul_match_sw,
                s.comments,
                s.extnd_cov_end_dt::date AS extnd_cov_end_dt,
                row_number() OVER (
                    PARTITION BY s.recon_month, s.appln_id, s.person_mbrsh_id
                    ORDER BY s.updated_dt DESC NULLS LAST, s.created_dt DESC NULLS LAST, s.seq_num DESC
                ) AS rn
            FROM interfaces.int_recon_menr_in_mly_stg s
            WHERE s.recon_month = p_recon_month
              AND s.processing_status = 'S'
        ) x
        WHERE rn = 1
    )
    UPDATE interfaces.int_recon_mly_snapshot t
    SET logical_id       = coalesce(m.logical_id, t.logical_id),
        subscr_id        = coalesce(m.subscr_id, t.subscr_id),
        mbr_id           = coalesce(m.mbr_id, t.mbr_id),
        relationship_cd  = coalesce(m.relationship_cd, t.relationship_cd),
        mul_match_sw     = coalesce(m.mul_match_sw, t.mul_match_sw),
        comments         = coalesce(m.comments, t.comments),
        extnd_cov_end_dt = coalesce(m.extnd_cov_end_dt, t.extnd_cov_end_dt),
        updated_by       = 'INT-REC-MST-DATA-MLY-PRC',
        updated_dt       = now()
    FROM latest_menr m
    WHERE t.recon_month = m.recon_month
      AND t.appln_id = m.appln_id
      AND t.person_mbrsh_id = m.person_mbrsh_id
      AND t.batch_run_id = p_batch_run_id;

    GET DIAGNOSTICS o_updated_count = ROW_COUNT;
END;
$procedure$;
```

Example call:
~~~sql
CALL interfaces.sp_load_int_recon_mly_snapshot_counts('202605', 1001, true, NULL, NULL);