-- Migration 015: Chat Tags — Tags de organização e filtro de sessões
-- Data: 15/06/2026
-- PRD: PRD-4-Tags-Chat.md

-- Tabela de tags por sessão
CREATE TABLE IF NOT EXISTS embaplan_chat_tags (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id TEXT NOT NULL,
  user_id UUID NOT NULL DEFAULT COALESCE(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid),
  tag TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(session_id, tag, user_id)
);

-- Índices para busca por tag e por sessão
CREATE INDEX IF NOT EXISTS idx_chat_tags_tag ON embaplan_chat_tags(tag);
CREATE INDEX IF NOT EXISTS idx_chat_tags_session ON embaplan_chat_tags(session_id);
CREATE INDEX IF NOT EXISTS idx_chat_tags_user ON embaplan_chat_tags(user_id);

-- RPC: adicionar tag a uma sessão
CREATE OR REPLACE FUNCTION embaplan_chat_add_tag(
  p_session_id TEXT,
  p_tag TEXT
) RETURNS VOID AS $$
BEGIN
  INSERT INTO embaplan_chat_tags (session_id, user_id, tag)
  VALUES (p_session_id, COALESCE(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid), lower(trim(p_tag)))
  ON CONFLICT (session_id, tag, user_id) DO NOTHING;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: remover tag de uma sessão
CREATE OR REPLACE FUNCTION embaplan_chat_remove_tag(
  p_session_id TEXT,
  p_tag TEXT
) RETURNS VOID AS $$
BEGIN
  DELETE FROM embaplan_chat_tags
  WHERE session_id = p_session_id
    AND user_id = COALESCE(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid)
    AND tag = lower(trim(p_tag));
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: listar tags de um usuário (com contagem de uso)
CREATE OR REPLACE FUNCTION embaplan_chat_list_user_tags()
RETURNS TABLE(tag TEXT, count BIGINT) AS $$
BEGIN
  RETURN QUERY
  SELECT t.tag, COUNT(*) as count
  FROM embaplan_chat_tags t
  WHERE t.user_id = COALESCE(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid)
  GROUP BY t.tag
  ORDER BY count DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: listar tags de uma sessão específica
CREATE OR REPLACE FUNCTION embaplan_chat_session_tags(
  p_session_id TEXT
) RETURNS TABLE(tag TEXT) AS $$
BEGIN
  RETURN QUERY
  SELECT t.tag
  FROM embaplan_chat_tags t
  WHERE t.session_id = p_session_id
    AND t.user_id = COALESCE(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid)
  ORDER BY t.tag;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: renomear tag globalmente (afeta todas as sessões do usuário)
CREATE OR REPLACE FUNCTION embaplan_chat_rename_tag(
  p_old_tag TEXT,
  p_new_tag TEXT
) RETURNS VOID AS $$
BEGIN
  UPDATE embaplan_chat_tags
  SET tag = lower(trim(p_new_tag))
  WHERE user_id = COALESCE(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid)
    AND tag = lower(trim(p_old_tag));
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: deletar tag globalmente (remove de todas as sessões do usuário)
CREATE OR REPLACE FUNCTION embaplan_chat_delete_tag(
  p_tag TEXT
) RETURNS VOID AS $$
BEGIN
  DELETE FROM embaplan_chat_tags
  WHERE user_id = COALESCE(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid)
    AND tag = lower(trim(p_tag));
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
