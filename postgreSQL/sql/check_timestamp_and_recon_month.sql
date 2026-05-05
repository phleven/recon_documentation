select 
	table_name, 
	column_name, 
	data_type 
from 
	information_schema.columns 
where 
	table_schema = 'interfaces' 
and 
	table_name in ('int_recon_mly_snapshot', 'int_recon_menr_in_mly_stg') 
and (lower(column_name) like '%dt%' 
    or lower(column_name) like '%date%' 
    or lower(column_name) like '%month%' 
    or lower(column_name) like '%time%') 
order by 
	table_name, 
	ordinal_position;