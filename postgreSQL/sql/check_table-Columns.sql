select 
	table_name, 
	column_name, 
	data_type, 
	ordinal_position 
from 
	information_schema.columns 
where 
	table_schema = 'interfaces' 
and 
	table_name in ('int_recon_mly_snapshot', 'int_recon_menr_in_mly_stg') 
order by 
	table_name, 
	ordinal_position;