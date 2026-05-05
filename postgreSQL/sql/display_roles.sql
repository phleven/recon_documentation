set search_path = recon;

SELECT
	rolname, -- Username
	rolsuper, -- Superuser status (true/false)
	rolcreaterole, -- Role creation privileges (true/false)
	rolcreatedb, -- Database creation privileges (true/false)
	rolcanlogin, -- Login capability (true/false)
	rolereplication
FROM 	
	pg_roles;