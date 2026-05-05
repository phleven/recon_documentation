-- 3) Columns published per table (PostgreSQL 15+ column-list publications)
-- If this returns all columns for a table, then all columns are published.
WITH pub_rel AS (
  SELECT
    p.pubname,
    n.nspname AS schema_name,
    c.relname AS table_name,
    c.oid      AS relid,
    pr.prattrs
  FROM pg_publication p
  JOIN pg_publication_rel pr ON pr.prpubid = p.oid
  JOIN pg_class c ON c.oid = pr.prrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
)
SELECT
  pubname,
  schema_name,
  table_name,
  a.attname AS column_name
FROM pub_rel r
JOIN pg_attribute a
  ON a.attrelid = r.relid
 AND a.attnum > 0
 AND NOT a.attisdropped
WHERE
  -- all columns if no column list was specified
  cardinality(r.prattrs) = 0
  OR a.attnum = ANY (r.prattrs)
ORDER BY pubname, schema_name, table_name, a.attnum;