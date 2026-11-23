# Query Timings — V_Nue Mail Database

**Project:** V_Nue Mail  
**Team:** V_nue_mail · Team No. T0043  
**Database:** PostgreSQL 18 (Postgres.app)  
**Measurement date:** 2026-11-23  
**Method:** `EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)` — 3 runs per query; avg/median/min/max recorded.  
**Dataset:** 501 users · 2,000 messages · 2,004 custom labels · 501 user_settings rows (seed data loaded from `dbms/03_schema.sql`)

> Raw EXPLAIN ANALYZE plans for all 10 queries are in [`dbms/plans/`](./plans/).

---

## 1. Summary Table

| Query | Description | avg\_ms | median\_ms | min\_ms | max\_ms | Scan Node |
|---|---|---|---|---|---|---|
| Q01 | Inbox messages for a user | 0.378 | 0.318 | 0.314 | 0.503 | Seq Scan on messages |
| Q02 | Unread message count per user | 1.955 | 1.877 | 1.828 | 2.160 | Seq Scan on messages + Index Only Scan on users |
| Q03 | Sent messages by a user | 0.209 | 0.201 | 0.198 | 0.229 | Seq Scan on messages |
| Q04 | Subject keyword search | 0.061 | 0.061 | 0.059 | 0.062 | Index Scan on idx\_messages\_created\_at |
| Q05 | Starred messages for a user | 0.179 | 0.174 | 0.166 | 0.196 | Seq Scan on messages |
| Q06 | Messages by category for a user | 0.235 | 0.236 | 0.233 | 0.237 | Seq Scan on messages |
| Q07 | User profile and settings lookup | 0.027 | 0.026 | 0.026 | 0.028 | Index Scan on users\_pkey + Index Scan on user\_settings\_pkey |
| Q08 | Custom labels for a user | 0.030 | 0.031 | 0.029 | 0.031 | Index Scan on users\_email\_key + Index Scan on custom\_labels\_user\_id\_name\_key |
| Q09 | Trash messages for a user | 0.165 | 0.165 | 0.161 | 0.168 | Seq Scan on messages |
| Q10 | Messages received in last 24 hours | 0.026 | 0.026 | 0.025 | 0.028 | Index Scan on idx\_messages\_created\_at |

**Total avg across all 10 queries: 3.265 ms**

---

## 2. Query Details

### Q01 — Inbox messages for a user

```sql
SELECT id, sender, subject, status, created_at
FROM messages
WHERE 'user1@vnuemail.local' = ANY(recipient)
  AND recipient_deleted = FALSE
  AND recipient_trash = FALSE
ORDER BY created_at DESC
LIMIT 50;
```

**avg: 0.378 ms | median: 0.318 ms | min: 0.314 ms | max: 0.503 ms**

**Observation:** Sequential scan on messages (2,000 rows). The `ANY(recipient)` predicate on a `TEXT[]` column cannot use the existing GIN-compatible index. At large scale (2 M+ messages) this will be a bottleneck. A GIN index on `recipient` would eliminate the full scan.

---

### Q02 — Unread message count per user

```sql
SELECT u.email, COUNT(m.id) AS unread_count
FROM users u
JOIN messages m ON u.email = ANY(m.recipient)
WHERE m.status = 'unread' AND m.recipient_deleted = FALSE
GROUP BY u.email
ORDER BY unread_count DESC
LIMIT 20;
```

**avg: 1.955 ms | median: 1.877 ms | min: 1.828 ms | max: 2.160 ms**

**Observation:** Slowest query (1.955 ms avg). Nested Loop: Seq Scan on messages filtered to 1,600 unread rows, then Index Only Scan on `users_email_key` per row. At 2 M messages the nested loop would scale poorly. A GIN index on `recipient` and an index on `status` would help.

---

### Q03 — Sent messages by a user

```sql
SELECT id, recipient, subject, created_at
FROM messages
WHERE sender = 'user1@vnuemail.local'
  AND sender_deleted = FALSE
ORDER BY created_at DESC
LIMIT 50;
```

**avg: 0.209 ms | median: 0.201 ms | min: 0.198 ms | max: 0.229 ms**

**Observation:** Seq Scan on messages. An index on `(sender, created_at DESC)` would convert this to an efficient index scan.

---

### Q04 — Subject keyword search

```sql
SELECT id, sender, subject, created_at
FROM messages
WHERE subject ILIKE '%Subject line 1%'
ORDER BY created_at DESC
LIMIT 20;
```

**avg: 0.061 ms | median: 0.061 ms | min: 0.059 ms | max: 0.062 ms**

**Observation:** Fastest read query (0.061 ms). Uses `idx_messages_created_at` for ORDER BY; the ILIKE filter is applied as a residual on the index scan. For wildcard-heavy production workloads a GIN trigram index on `subject` would be more selective.

---

### Q05 — Starred messages for a user

```sql
SELECT id, sender, subject, created_at
FROM messages
WHERE 'user1@vnuemail.local' = ANY(recipient)
  AND recipient_starred = TRUE
ORDER BY created_at DESC;
```

**avg: 0.179 ms | median: 0.174 ms | min: 0.166 ms | max: 0.196 ms**

**Observation:** Seq Scan. Same `ANY(recipient)` limitation as Q01.

---

### Q06 — Messages by category for a user

```sql
SELECT id, sender, subject, created_at
FROM messages
WHERE 'user1@vnuemail.local' = ANY(recipient)
  AND category = 'primary'
ORDER BY created_at DESC
LIMIT 50;
```

**avg: 0.235 ms | median: 0.236 ms | min: 0.233 ms | max: 0.237 ms**

**Observation:** Seq Scan. An index on `(category, created_at DESC)` would help for category-filtered views.

---

### Q07 — User profile and settings lookup

```sql
SELECT u.email, u.display_name, s.theme, s.density, s.signature
FROM users u
JOIN user_settings s ON u.id = s.user_id
WHERE u.email = 'user1@vnuemail.local';
```

**avg: 0.027 ms | median: 0.026 ms | min: 0.026 ms | max: 0.028 ms**

**Observation:** Fastest query overall (0.027 ms). Uses `users_email_key` unique index to find the user, then PK index on `user_settings`. Scales perfectly; no improvements needed.

---

### Q08 — Custom labels for a user

```sql
SELECT cl.name, cl.color
FROM custom_labels cl
JOIN users u ON cl.user_id = u.id
WHERE u.email = 'user1@vnuemail.local';
```

**avg: 0.030 ms | median: 0.031 ms | min: 0.029 ms | max: 0.031 ms**

**Observation:** Index-driven join (email → user PK → custom_labels FK). Very efficient; no improvements needed.

---

### Q09 — Trash messages for a user

```sql
SELECT id, sender, subject, created_at
FROM messages
WHERE 'user1@vnuemail.local' = ANY(recipient)
  AND recipient_trash = TRUE
ORDER BY created_at DESC;
```

**avg: 0.165 ms | median: 0.165 ms | min: 0.161 ms | max: 0.168 ms**

**Observation:** Seq Scan. Very few rows match `recipient_trash = TRUE` in the seed dataset (0 for this user), so the scan exits quickly. At scale a partial index `WHERE recipient_trash = TRUE` would avoid full table scans for rare flags.

---

### Q10 — Messages received in last 24 hours

```sql
SELECT COUNT(*) AS recent_count
FROM messages
WHERE 'user1@vnuemail.local' = ANY(recipient)
  AND created_at >= NOW() - INTERVAL '24 hours';
```

**avg: 0.026 ms | median: 0.026 ms | min: 0.025 ms | max: 0.028 ms**

**Observation:** Uses `idx_messages_created_at` to prune to recent rows, then filters by recipient. Scales well for time-bounded queries.

---

## 3. Identified Bottlenecks and Recommended Indexes

| Issue | Affected Queries | Recommended Fix |
|---|---|---|
| `ANY(recipient)` has no GIN index | Q01, Q02, Q05, Q06, Q09 | `CREATE INDEX idx_messages_recipient_gin ON messages USING GIN(recipient);` |
| No index on `sender` | Q03 | `CREATE INDEX idx_messages_sender ON messages(sender, created_at DESC);` |
| No trigram index on `subject` | Q04 | `CREATE INDEX idx_messages_subject_trgm ON messages USING GIN(subject gin_trgm_ops);` |
| Nested Loop join at scale | Q02 | GIN on `recipient` reduces inner loop iterations |
| Boolean flag scans (`recipient_trash`, `recipient_starred`) | Q05, Q09 | Partial indexes: `CREATE INDEX ... WHERE recipient_trash = TRUE;` |

---

## 4. Scalability Notes

At seed scale (2,000 messages, 501 users) all queries complete in under 2 ms. The two critical concerns at 1 M+ message scale are:

1. **Q02 (unread count):** The nested loop over all unread messages × index lookup per recipient will scale as O(unread × log(users)). A GIN index on `recipient` and materialised unread counters (or a Redis cache) would be essential.
2. **Q01/Q05/Q06/Q09 (array predicate):** Every inbox-style query does a full Seq Scan filtered by `ANY(recipient)`. At 10 M messages this becomes unacceptable. A GIN index on `recipient` is the highest-priority single fix.
