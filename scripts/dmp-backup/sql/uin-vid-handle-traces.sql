-- UIN / VID / Handle database traces for DMP internship
-- Run against qajava21 Postgres (mosip_idrepo + mosip_idmap).
-- Note: UIN/VID values are stored hashed/encrypted; plaintext is not always available.

\echo '=== mosip_idrepo.idrepo.uin (UIN identity rows) ==='
SELECT
  uin_ref_id,
  left(uin, 32) AS uin_prefix,
  left(uin_hash, 32) AS uin_hash_prefix,
  reg_id,
  bio_ref_id,
  status_code,
  cr_dtimes,
  upd_dtimes,
  is_deleted
FROM idrepo.uin
WHERE COALESCE(is_deleted, false) = false
ORDER BY cr_dtimes DESC
LIMIT 500;

\echo '=== mosip_idrepo.idrepo.handle (Handle <-> UIN hash) ==='
SELECT
  id,
  left(uin_hash, 32) AS uin_hash_prefix,
  handle,
  left(handle_hash, 32) AS handle_hash_prefix,
  cr_by,
  cr_dtimes
FROM idrepo.handle
ORDER BY cr_dtimes DESC
LIMIT 500;

\echo '=== Join: Handle with UIN identity status ==='
SELECT
  h.handle,
  left(h.handle_hash, 32) AS handle_hash_prefix,
  left(h.uin_hash, 32) AS uin_hash_prefix,
  u.uin_ref_id,
  u.reg_id,
  u.status_code AS uin_status,
  u.cr_dtimes AS uin_created,
  h.cr_dtimes AS handle_created
FROM idrepo.handle h
LEFT JOIN idrepo.uin u
  ON u.uin_hash = h.uin_hash
 AND COALESCE(u.is_deleted, false) = false
ORDER BY h.cr_dtimes DESC
LIMIT 500;

\echo '=== Counts ==='
SELECT 'uin_active' AS metric, count(*) AS value FROM idrepo.uin WHERE COALESCE(is_deleted, false) = false
UNION ALL
SELECT 'handle_total', count(*) FROM idrepo.handle;
