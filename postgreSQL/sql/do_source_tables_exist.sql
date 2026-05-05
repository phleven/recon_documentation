select 
	table_schema, 
	table_name 
from 
	information_schema.tables 
where 
	table_schema = 'interfaces' 
and
	table_name in ('int_recon_mly_snapshot', 'int_recon_menr_in_mly_stg') 
order by 
	table_name; 