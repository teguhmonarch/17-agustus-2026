# Customer Intelligence Platform — 15M Records

17 Agustus Coding Festival. A search + data-quality + duplicate-detection
platform over **14,999,896 customer records** (4 relational tables, ~22M rows total).

**Stack:** Node.js + Express (no TypeScript) · PostgreSQL 14 · vanilla dashboard UI.
All metrics are computed **live** against PostgreSQL — nothing is pre-computed.

## Quick start

**Already running — nothing to build:** <http://168.144.244.142:3000>
(dashboard) · <http://168.144.244.142:3000/docs.html> (API reference) ·
<http://168.144.244.142:3000/api/health> (readiness + record count).

To run it yourself you need the organizers' dump,
`challenge_db_anonymized_v2.sql.gz` (1.9GB, provided on the challenge VPS at
`/app/data/`). It is not in this repo. Point `DUMP` at wherever you put it:

```bash
DUMP=/app/data/challenge_db_anonymized_v2.sql.gz   # organizers' dump

docker compose up -d db          # start PostgreSQL 14 (tuned)
# restore the dump into the cip database (~25 min for 15M rows):
gunzip -c "$DUMP" \
  | docker exec -i cip-pg psql -U postgres -d cip -v ON_ERROR_STOP=0
# build indexes (pg_trgm + btree):
docker exec -i cip-pg psql -U postgres -d cip < db/indexes.sql
docker compose up -d api         # start the API + dashboard
curl http://localhost:3000/api/health
```

The database name is `cip` and the Postgres container is `cip-pg`, so
`docker exec -it cip-pg psql -U postgres -d cip` opens a shell against the
loaded data. Index build (`db/indexes.sql`) takes a few minutes — the API
answers before it finishes, just slower.

Dashboard: <http://localhost:3000> · API base: `http://localhost:3000`

## Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/health`, `/health` | readiness + total record count |
| GET | `/api/search?q=&type=&limit=&offset=` | search: `email`/`phone`/`user_id`/`name` |
| GET | `/api/quality` | full data-quality report (live) |
| GET | `/api/metrics` | compact quality summary |
| GET | `/api/duplicates/:user_id?threshold=&limit=` | duplicates for one user (similarity) |
| POST | `/api/duplicates` | global duplicate pairs (bounded) or `{user_id}` |
| GET | `/api/duplicates/find?method=ip_address\|order_history\|activity_pattern\|all&limit=50` | duplicate groups by shared attribute |
| GET | `/api/user-profile/:user_id` | user + orders + transactions + activity (4-table JOIN) |

### Examples

```bash
curl "http://localhost:3000/api/search?q=komang&type=name&limit=10&offset=0"
curl "http://localhost:3000/api/search?q=081234567890&type=phone"
curl  http://localhost:3000/api/quality
curl "http://localhost:3000/api/duplicates/1000?threshold=0.7"
curl -X POST http://localhost:3000/api/duplicates
curl "http://localhost:3000/api/duplicates/find?method=ip_address&limit=50"
curl "http://localhost:3000/api/duplicates/find?method=all&limit=50"
curl  http://localhost:3000/api/user-profile/311790
```

## Design

- **Search** — exact types (`email`/`phone`/`user_id`) hit btree indexes; `name`
  uses a `pg_trgm` GIN index for fast fuzzy/substring matching, ranked by
  trigram similarity. Phone numbers are masked in responses.
- **Quality** — one single-pass conditional aggregation over `ws_user` plus a
  duplicate-group pass, cached 60s so repeated dashboard loads stay cheap.
- **Duplicates** — composite score `email*0.4 + phone*0.4 + name_sim*0.2`;
  name similarity is normalized Levenshtein; candidates come from indexed
  exact email/phone matches and trigram name matches (no full table scan).
- **Duplicate groups** (`/api/duplicates/find`) — three cross-table strategies,
  each carrying its own confidence weight:

  | `method` | signal | confidence | score |
  |---|---|---|---|
  | `ip_address` | users sharing an IP in `ws_user_activity` | HIGH | 1.00 |
  | `order_history` | identical order amount on the same day | MEDIUM | 0.60 |
  | `activity_pattern` | same activity type within the same minute | LOW | 0.30 |
  | `all` | weighted merge, ordered by score then group size | — | — |

  Each strategy is a full-table aggregate (5-13s), so the top 500 groups per
  strategy are computed at boot and refreshed in the background — requests are
  served from cache in ~5ms and never block on the aggregate.
- **Load** — pool (max 60), gzip compression, per-statement 8s timeout,
  bounded result/count queries. Measured on the 4 vCPU VPS, 100 concurrent
  connections for 60s against `/api/user-profile/:user_id` over 100k distinct
  user ids (cache-miss heavy): 68,294 requests, **100% success, avg 88ms,
  p50 88ms, p99 168ms**, zero errors.
- **Bulkhead** — name search is the only DB-heavy read path (it pins Postgres at
  355% of 4 vCPUs while Node idles at 44%), so it runs behind an 8-slot
  semaphore. Excess name queries wait in Node instead of draining the pool.
  Verified: flooding `/api/search?type=name` at 100 concurrent leaves
  `/api/user-profile` untouched — 968 rps, 100% success, p99 227ms, identical
  to running it alone.
- **Pre-serialized duplicate groups** — a group response is ~150KB and identical
  between requests, so each `(method, limit)` body is serialized once into a
  Buffer and only `took_ms` is appended per request. Throughput went from
  229 to 867 rps (`method=all`) and p99 from 5000ms (3% timeouts) to 216ms.

See [DATABASE_NOTES.md](DATABASE_NOTES.md) for schema and index detail.
