# Supabase Schema Export

Full export of the Postgres `public` schema for Supabase project **`smddzybxebwhfnitxuyp`**.

These files are a snapshot of the **live database schema as of 2026-08-14**. They are kept
in git as a reference so nothing is lost, and to allow a manual rebuild if needed.

> These are **reference / rebuild exports, not auto-applied migrations.** Nothing here runs
> automatically. Review before executing any of it against a database.

## Files

| File | Contents |
|------|----------|
| `01_tables.sql` | All 57 base tables (`CREATE TABLE IF NOT EXISTS`) with their columns, followed by 65 primary-key / unique / foreign-key constraints as `ALTER TABLE ... ADD CONSTRAINT`. |
| `02_views.sql` | All 36 views (`CREATE OR REPLACE VIEW`). |
| `03_functions.sql` | All 44 functions and procedures (`pg_get_functiondef` output, verbatim). |
| `04_cron.sql` | 20 scheduled `pg_cron` jobs, expressed as `cron.schedule(...)` calls. |
| `05_policies.sql` | 38 RLS policies (informational comment blocks) plus the list of 45 tables that have RLS enabled. |

## Notes

- Column definitions capture type, nullability and defaults. Indexes (other than those implied
  by PK/unique constraints), triggers, grants and extensions are **not** included in this export.
- `05_policies.sql` is informational (the policy predicates are written as comments), not runnable
  `CREATE POLICY` statements.
- Function bodies are reproduced exactly as returned by `pg_get_functiondef`, including their
  `SECURITY DEFINER` / `search_path` settings.
- Object counts at export time: 57 tables, 65 constraints, 36 views, 44 functions, 20 cron jobs,
  38 policies, 45 RLS-enabled tables.
