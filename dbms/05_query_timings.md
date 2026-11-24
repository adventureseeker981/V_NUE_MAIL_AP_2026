# Query Timings — V_Nue Mail Database

**Project:** V_Nue Mail  
**Team:** V_nue_mail · Team No. T0043  
**Database:** PostgreSQL 18 (Postgres.app)  
**Measurement date:** 2026-11-23  
**Method:** `EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)` — 3 runs per query; individual run times and average recorded.  
**Dataset:** 501 users · 2,000 messages · 2,004 custom labels · 501 user_settings rows

> Raw EXPLAIN ANALYZE plans for all 10 queries are in [`dbms/plans/`](./plans/).

---

## Timing Table

| Query | Type | What it does | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) | Scan type |
|-------|------|--------------|----------:|----------:|----------:|-------------:|-----------|
| R1 | READ | Inbox: messages received by a user (not deleted/trashed), newest first | 0.503 | 0.318 | 0.314 | 0.378 | Seq Scan on messages |
| R2 | READ | Unread count per user (top 20) | 2.160 | 1.877 | 1.828 | 1.955 | Seq Scan on messages + Index Only Scan on users |
| R3 | READ | Sent messages by a user, newest first | 0.201 | 0.229 | 0.198 | 0.209 | Seq Scan on messages |
| R4 | READ | Subject keyword search (ILIKE) | 0.059 | 0.061 | 0.062 | 0.061 | Index Scan on idx_messages_created_at |
| R5 | READ | Starred messages for a user | 0.166 | 0.174 | 0.196 | 0.179 | Seq Scan on messages |
| R6 | READ | Messages by category (primary/social/promotions) for a user | 0.236 | 0.233 | 0.237 | 0.235 | Seq Scan on messages |
| R7 | READ | User profile and settings (theme, density, signature) | 0.028 | 0.026 | 0.026 | 0.027 | Index Scan on users_email_key + user_settings_pkey |
| R8 | READ | Custom labels for a user | 0.031 | 0.031 | 0.029 | 0.030 | Index Scan on users_email_key + custom_labels FK |
| R9 | READ | Trash messages for a user | 0.165 | 0.161 | 0.168 | 0.165 | Seq Scan on messages |
| R10 | READ | Count of messages received in the last 24 hours | 0.028 | 0.025 | 0.026 | 0.026 | Index Scan on idx_messages_created_at |

---

## Notes on Individual Runs

- **Run 1** is cold (plan cache warming); **Runs 2 and 3** reflect warmed-cache performance.
- Averages are computed as `(Run 1 + Run 2 + Run 3) / 3`.
- Write queries were not measured in this project (no W-type queries yet); all 10 queries are READ operations.
- Times are `Execution Time` from `EXPLAIN ANALYZE` — planning time is excluded.

---

## Bottlenecks Identified

| Query | Issue | Recommended Fix |
|---|---|---|
| R1, R5, R6, R9 | `ANY(recipient)` on `TEXT[]` — no GIN index → Seq Scan on 2,000 rows | `CREATE INDEX idx_messages_recipient_gin ON messages USING GIN(recipient);` |
| R2 | Nested loop: Seq Scan on messages × Index lookup per user — scales as O(n×log m) | GIN index on `recipient` reduces inner iterations |
| R3 | No index on `sender` — Seq Scan for every sent-mail view | `CREATE INDEX idx_messages_sender ON messages(sender, created_at DESC);` |
| R4 | ILIKE with leading `%` cannot use a B-tree index on `subject` | `CREATE INDEX idx_messages_subject_trgm ON messages USING GIN(subject gin_trgm_ops);` |

---

## Scalability Notes

At seed scale (2,000 messages) all queries finish under 2.2 ms. At 1 M+ messages, the `ANY(recipient)` queries (R1, R2, R5, R6, R9) will degrade linearly without a GIN index on `recipient`. A GIN index is the single highest-priority optimization for this schema.
