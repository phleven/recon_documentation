select 
	'int_recon_mly_snapshot' as table_name, 
	count(*) as row_count 
from 
	interfaces.int_recon_mly_snapshot 
union all 
select 
	'int_recon_menr_in_mly_stg', count(*) 
from 
	interfaces.int_recon_menr_in_mly_stg;