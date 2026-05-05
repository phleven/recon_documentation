-- 4) Replica identity (important for UPDATE/DELETE event contents)
SELECT
  n.nspname AS schema_name,
  c.relname AS table_name,
  c.relreplident AS replident_code,
  CASE c.relreplident
    WHEN 'd' THEN 'DEFAULT (PK if exists)'
    WHEN 'n' THEN 'NOTHING'
    WHEN 'f' THEN 'FULL'
    WHEN 'i' THEN 'INDEX'
  END AS replica_identity
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'r'
ORDER BY n.nspname, c.relname;