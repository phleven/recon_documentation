-- 1) Publications and which operations they publish
SELECT
  p.pubname,
  p.puballtables,
  p.pubinsert,
  p.pubupdate,
  p.pubdelete,
  p.pubtruncate
FROM pg_publication p
ORDER BY p.pubname;