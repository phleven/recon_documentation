-- interfaces.int_recon_mly_snapshot definition

-- Drop table

-- DROP TABLE interfaces.int_recon_mly_snapshot;

CREATE TABLE interfaces.int_recon_mly_snapshot (
	seq_num int8 DEFAULT nextval('interfaces.int_recon_mly_snapshot_seq'::regclass) NOT NULL,
	recon_month varchar(6) NULL,
	appln_id numeric(12) NULL,
	logical_id varchar(15) NULL,
	subscr_id varchar(20) NULL,
	mbr_id varchar(20) NULL,
	first_na varchar(30) NULL,
	middle_na varchar(30) NULL,
	last_na varchar(30) NULL,
	birth_dt date NULL,
	subscr_ssn_num varchar(9) NULL,
	claim_num varchar(50) NULL,
	member_type varchar(12) NULL,
	plan_cd varchar NULL,
	matched_sw varchar(1) NULL,
	mapped_sw varchar(1) NULL,
	mul_match_sw varchar(1) NULL,
	"comments" varchar NULL,
	crtd_dt date NULL,
	cov_str_dt date NULL,
	cov_end_dt date NULL,
	phone_num numeric(15) NULL,
	email varchar(1000) NULL,
	adr_str_1 varchar(64) NULL,
	adr_str_2 varchar(64) NULL,
	adr_str_3 varchar(64) NULL,
	city_na varchar(35) NULL,
	state_cd varchar(10) NULL,
	zip_code varchar(10) NULL,
	ctry_cd varchar(10) NULL,
	is_primary varchar(1) NULL,
	person_mbrsh_id numeric(12) NULL,
	processing_status varchar(1) NULL,
	carrier_name varchar(4) NULL,
	mbr_ssn_num varchar(9) NULL,
	batch_run_id int8 NULL,
	error_cd varchar(10) NULL,
	created_by varchar(50) NULL,
	created_dt timestamp NULL,
	updated_by varchar(50) NULL,
	updated_dt timestamp NULL,
	payroll_office_number varchar(8) NULL,
	relationship_cd varchar(2) NULL,
	extnd_cov_end_dt date NULL,
	sex_cd varchar(1) NULL,
	home_adr_str_1 varchar(64) NULL,
	home_adr_str_2 varchar(64) NULL,
	home_adr_str_3 varchar(64) NULL,
	home_city_na varchar(35) NULL,
	home_state_cd varchar(10) NULL,
	home_zip_code varchar(10) NULL,
	home_ctry_cd varchar(10) NULL,
	CONSTRAINT int_recon_snapshot_pk PRIMARY KEY (seq_num)
);
CREATE INDEX int_recon_mly_snapshot_1n ON interfaces.int_recon_mly_snapshot USING btree (carrier_name, recon_month, claim_num);
CREATE INDEX int_recon_mly_snapshot_2n ON interfaces.int_recon_mly_snapshot USING btree (processing_status, subscr_id, mbr_id);
CREATE INDEX int_recon_mly_snapshot_3n ON interfaces.int_recon_mly_snapshot USING btree (carrier_name, recon_month, mbr_ssn_num);
CREATE INDEX int_recon_mly_snapshot_4n ON interfaces.int_recon_mly_snapshot USING btree (person_mbrsh_id);
CREATE INDEX int_recon_mly_snapshot_5n ON interfaces.int_recon_mly_snapshot USING btree (carrier_name, recon_month, first_na, last_na, birth_dt);