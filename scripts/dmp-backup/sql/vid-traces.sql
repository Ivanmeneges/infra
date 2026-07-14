-- VID database traces for DMP internship (mosip_idmap)
-- Run against qajava21 Postgres database mosip_idmap.

\echo '=== mosip_idmap.idmap.vid (VID <-> UIN mapping) ==='
SELECT
  id,
  vid,
  left(uin_hash, 32) AS uin_hash_prefix,
  left(uin, 32) AS uin_encrypted_prefix,
  vidtyp_code,
  generated_dtimes,
  expiry_dtimes,
  status_code,
  cr_dtimes,
  upd_dtimes,
  is_deleted
FROM idmap.vid
WHERE COALESCE(is_deleted, false) = false
ORDER BY generated_dtimes DESC
LIMIT 500;

\echo '=== Active VIDs by type ==='
SELECT
  vidtyp_code,
  status_code,
  count(*) AS cnt
FROM idmap.vid
WHERE COALESCE(is_deleted, false) = false
GROUP BY vidtyp_code, status_code
ORDER BY vidtyp_code, status_code;

\echo '=== Salt tables present (needed to interpret hashes) ==='
SELECT 'uin_hash_salt' AS table_name, count(*) AS rows FROM idmap.uin_hash_salt
UNION ALL
SELECT 'uin_encrypt_salt', count(*) FROM idmap.uin_encrypt_salt;
