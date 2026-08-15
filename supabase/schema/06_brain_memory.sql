-- ============================================================
-- Mémoire permanente des bots traders (voir docs/brain/MEMOIRE.md)
-- Appliqué le 2026-08-15. Archive append-only + trigger d'archivage.
-- ============================================================

-- Archive PERMANENTE (jamais rognée) des leçons & erreurs de chaque bot.
CREATE TABLE IF NOT EXISTS public.brain_lessons (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  archimage text NOT NULL,
  run_id text NOT NULL,
  kind text NOT NULL DEFAULT 'learning',   -- 'learning' | 'mistake'
  bias text,
  eval text,
  pnl numeric,
  dd numeric,
  at timestamptz DEFAULT now(),
  UNIQUE (archimage, run_id, kind)
);
CREATE INDEX IF NOT EXISTS idx_brain_lessons_archimage_at ON public.brain_lessons(archimage, at DESC);

-- À chaque écriture du cerveau, archive la dernière leçon + la dernière erreur (dédup).
CREATE OR REPLACE FUNCTION public.archive_brain_lessons() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
declare l jsonb; m jsonb; n int;
begin
  if NEW.archimage not in ('JU','SYL','GIL') then return NEW; end if;
  n := jsonb_array_length(coalesce(NEW.learnings,'[]'::jsonb));
  if n > 0 then
    l := NEW.learnings -> (n-1);
    if l ? 'run' then
      insert into public.brain_lessons(archimage, run_id, kind, bias, eval, pnl, dd)
      values (NEW.archimage, l->>'run', 'learning', l->>'bias', l->>'eval',
              nullif(l->>'pnl','')::numeric, nullif(l->>'dd','')::numeric)
      on conflict (archimage, run_id, kind) do nothing;
    end if;
  end if;
  n := jsonb_array_length(coalesce(NEW.mistakes_history,'[]'::jsonb));
  if n > 0 then
    m := NEW.mistakes_history -> (n-1);
    if m ? 'run' then
      insert into public.brain_lessons(archimage, run_id, kind, eval, pnl, dd)
      values (NEW.archimage, m->>'run', 'mistake', m->>'eval',
              nullif(m->>'pnl','')::numeric, nullif(m->>'dd','')::numeric)
      on conflict (archimage, run_id, kind) do nothing;
    end if;
  end if;
  return NEW;
end $fn$;

DROP TRIGGER IF EXISTS trg_archive_brain_lessons ON public.oracle_brain_state;
CREATE TRIGGER trg_archive_brain_lessons
  AFTER INSERT OR UPDATE ON public.oracle_brain_state
  FOR EACH ROW EXECUTE FUNCTION public.archive_brain_lessons();

-- Snapshot complet de la mémoire (pour la sauvegarde GitHub quotidienne, workflow brain-backup.yml).
CREATE OR REPLACE FUNCTION public.brain_snapshot() RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path TO 'public' STABLE AS $$
  SELECT jsonb_build_object(
    'snapshot_at', now(),
    'source', 'brain_lessons (archive permanente) — source de verite = Supabase',
    'doctrines', (SELECT jsonb_object_agg(archimage, jsonb_build_object('win_rate',win_rate,'current_bias',current_bias))
                  FROM oracle_brain_state WHERE archimage IN ('JU','SYL','GIL')),
    'lecons_epinglees', (SELECT jsonb_object_agg(archimage, learnings->0)
                  FROM oracle_brain_state WHERE archimage IN ('JU','SYL','GIL') AND (learnings->0->>'pinned')='true'),
    'totaux', (SELECT jsonb_object_agg(archimage||'_'||kind, n) FROM (
                  SELECT archimage, kind, count(*) n FROM brain_lessons GROUP BY archimage, kind) t),
    'lessons', (SELECT jsonb_agg(to_jsonb(bl) ORDER BY bl.archimage, bl.at)
                FROM (SELECT archimage, run_id, kind, bias, eval, pnl, dd, at FROM brain_lessons) bl)
  );
$$;
GRANT EXECUTE ON FUNCTION public.brain_snapshot() TO anon;
