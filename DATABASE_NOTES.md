# Database Notes

## Source

`challenge_db_anonymized_v2.sql.gz` — plain `pg_dump` (PostgreSQL 14.23),
1.9 GB gzip. Restored as-is into database `cip`. No schema changes to the
source tables; only added indexes + `pg_trgm`.

## Row counts (verified after import)

| Table | Rows |
|-------|-----:|
| ws_user | 14,999,896 |
| ws_orders | 2,999,986 |
| ws_transactions | 2,400,548 |
| ws_user_activity | 2,000,000 |

Also present: `ws_user_preferences`, `test_table` (unused by the API).

## Key columns (ws_user)

`user_id` (PK, bigint), `user_name`, `full_name`, `user_email`, `msisdn`,
`status` (-1/0/1), `sex`, `birth_date`, `location`, `hobbies` (emoji/NULLs),
`about_me`, `create_time`, `update_time`, `last_login`.
Note: the dump uses `create_time` (mapped to `created_at` in API responses).

## Indexes added (`db/indexes.sql`)

| Index | Purpose |
|-------|---------|
| `ws_user_pk` (from dump) | `user_id` exact lookup |
| `idx_user_email_lower` on `lower(user_email)` | case-insensitive exact email search + dup detection |
| `idx_user_msisdn` on `msisdn` | exact phone search |
| `idx_user_msisdn_norm` on normalized digits | phone search tolerant of formatting |
| `idx_user_fullname_trgm` GIN `gin_trgm_ops` | fuzzy/partial name search + name similarity |
| `idx_orders_user`, `idx_tx_order`, `idx_activity_user` | relational joins |

Extension: `pg_trgm` (trigram matching for `ILIKE '%..%'` and `similarity()`).

## PostgreSQL tuning (docker-compose)

`shared_buffers=2GB`, `effective_cache_size=5GB`, `maintenance_work_mem=1GB`,
`work_mem=64MB`, `max_wal_size=8GB`, `synchronous_commit=off`,
`max_connections=200`, parallel workers enabled. `shm_size=1gb` on the
container. Box: 4 vCPU / 8 GB RAM / Ubuntu 24.04.

## Query strategy

- Exact search → index scan, `LIMIT/OFFSET` pagination.
- Name search → GIN trigram index; count bounded to 1000 to cap latency.
- Quality → single-pass `COUNT(*) FILTER (...)`; duplicate groups via
  `GROUP BY ... HAVING count > 1`; result cached 60s (still recomputed live).
- Duplicates → indexed exact email/phone candidates + trigram name candidates,
  scored in the app layer; never a full table scan.
