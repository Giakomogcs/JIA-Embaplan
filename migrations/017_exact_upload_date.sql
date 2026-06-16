-- Migration 017: Exact Upload Date — Suporte a salvar data exata selecionada no calendário
-- Data: 16/06/2026

CREATE OR REPLACE FUNCTION embaplan_create_month_batch(
  p_user_id      UUID DEFAULT NULL,
  p_periodo      TEXT DEFAULT NULL,
  p_rotulo       TEXT DEFAULT NULL,
  p_arquivo_nome TEXT DEFAULT NULL,
  p_replace      BOOLEAN DEFAULT TRUE
)
RETURNS BIGINT
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
  _periodo  DATE;
  _batch_id BIGINT;
  _rotulo   TEXT;
BEGIN
  -- Normaliza o período para a data exata se vier YYYY-MM-DD.
  -- Se vier YYYY-MM, normaliza para o dia 1. Se vazio, usa a data atual (dia atual, não truncado para o mês).
  IF p_periodo IS NULL OR TRIM(p_periodo) = '' THEN
    _periodo := NOW()::DATE;
  ELSIF p_periodo ~ '^[0-9]{4}-[0-9]{2}$' THEN
    _periodo := to_date(p_periodo || '-01', 'YYYY-MM-DD');
  ELSIF p_periodo ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN
    _periodo := to_date(p_periodo, 'YYYY-MM-DD');
  ELSE
    _periodo := p_periodo::DATE;
  END IF;

  _rotulo := COALESCE(
    NULLIF(TRIM(p_rotulo), ''),
    initcap(to_char(_periodo, 'TMMonth YYYY'))
  );

  -- Reenvio idempotente: remove o batch anterior do mesmo dia/período.
  IF p_replace THEN
    DELETE FROM embaplan_upload_batch WHERE periodo = _periodo;
  END IF;

  INSERT INTO embaplan_upload_batch (user_id, rotulo, arquivo_nome, periodo)
  VALUES (p_user_id, _rotulo, p_arquivo_nome, _periodo)
  RETURNING id INTO _batch_id;

  RETURN _batch_id;
END;
$$;

GRANT EXECUTE ON FUNCTION embaplan_create_month_batch(UUID, TEXT, TEXT, TEXT, BOOLEAN) TO authenticated;
NOTIFY pgrst, 'reload schema';
