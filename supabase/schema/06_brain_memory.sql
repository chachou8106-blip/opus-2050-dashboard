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
