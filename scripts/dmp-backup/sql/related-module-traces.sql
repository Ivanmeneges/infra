-- Related module traces that help correlate UIN/VID/Handle work
-- Run each section against the named database on qajava21.

-- ========== mosip_regprc ==========
-- \c mosip_regprc
\echo '=== regprc: recent registration packets (if table exists) ==='
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
  AND (
    table_name ILIKE '%registration%'
    OR table_name ILIKE '%packet%'
    OR table_name ILIKE '%uin%'
  )
ORDER BY 1, 2;

-- ========== mosip_credential ==========
-- \c mosip_credential
\echo '=== credential: transaction-ish tables ==='
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
  AND (
    table_name ILIKE '%credential%'
    OR table_name ILIKE '%transaction%'
  )
ORDER BY 1, 2;

-- ========== mosip_ida ==========
-- \c mosip_ida
\echo '=== ida: identity / UIN / handle related tables ==='
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
  AND (
    table_name ILIKE '%uin%'
    OR table_name ILIKE '%vid%'
    OR table_name ILIKE '%handle%'
    OR table_name ILIKE '%identity%'
    OR table_name ILIKE '%credential%'
  )
ORDER BY 1, 2;

-- ========== mosip_resident ==========
-- \c mosip_resident
\echo '=== resident: tables mentioning uin/vid/handle/event ==='
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
  AND (
    table_name ILIKE '%uin%'
    OR table_name ILIKE '%vid%'
    OR table_name ILIKE '%handle%'
    OR table_name ILIKE '%event%'
    OR table_name ILIKE '%request%'
  )
ORDER BY 1, 2;
