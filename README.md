# Customer Intelligence Platform — 15M Records

17 Agustus Coding Festival. A search + data-quality + duplicate-detection
platform over **14,999,896 customer records** (4 relational tables, ~22M rows total).

**Stack:** Node.js + Express (no TypeScript) · PostgreSQL 14 · vanilla dashboard UI.
All metrics are computed **live** against PostgreSQL — nothing is pre-computed.

## Quick start

```bash
docker compose up -d db          # start PostgreSQL 14 (tuned)
# restore the provided dump into the cip database:
gunzip -c /app/data/challenge_db_anonymized_v2.sql.gz \
  | docker exec -i cip-pg psql -U postgres -d cip -v ON_ERROR_STOP=0
# build indexes (pg_trgm + btree):
docker exec -i cip-pg psql -U postgres -d cip < db/indexes.sql
docker compose up -d api         # start the API + dashboard
curl http://localhost:3000/api/health
```

Dashboard: <http://localhost:3000> · API base: `http://localhost:3000`

## Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/health`, `/health` | readiness + total record count |
| GET | `/api/search?q=&type=&limit=&offset=` | search: `email`/`phone`/`user_id`/`name` |
| GET | `/api/quality` | full data-quality report (live) |
| GET | `/api/metrics` | compact quality summary |
| GET | `/api/duplicates/:user_id?threshold=&limit=` | duplicates for one user |
| POST | `/api/duplicates` | global duplicate pairs (bounded) or `{user_id}` |

### Examples

```bash
curl "http://localhost:3000/api/search?q=komang&type=name&limit=10&offset=0"
curl "http://localhost:3000/api/search?q=081234567890&type=phone"
curl  http://localhost:3000/api/quality
curl "http://localhost:3000/api/duplicates/1000?threshold=0.7"
curl -X POST http://localhost:3000/api/duplicates
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
- **Load** — pool (max 60), gzip compression, per-statement 8s timeout,
  bounded result/count queries.

See [DATABASE_NOTES.md](DATABASE_NOTES.md) for schema and index detail.
