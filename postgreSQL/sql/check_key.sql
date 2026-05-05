select 
    tc.table_schema, 
    tc.table_name, 
    tc.constraint_name, 
    tc.constraint_type, 
    kcu.column_name 
from 
	information_schema.table_constraints tc 
join 
	information_schema.key_column_usage kcu 
on 
	tc.constraint_name = kcu.constraint_name 
and 
	tc.table_schema = kcu.table_schema 
where 
	tc.table_schema = 'interfaces' 
and 
	tc.table_name in ('int_recon_mly_snapshot', 'int_recon_menr_in_mly_stg') 
and 
	tc.constraint_type in ('PRIMARY KEY', 'UNIQUE') 
order by 
	tc.table_name, 
	kcu.ordinal_position;