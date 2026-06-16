-- =============================================
-- Embaplan — 018: Gerenciamento de planilhas (batches) + ciclo de recomendações
-- 1) Corrige embaplan_portfolio_evolution (coluna ticket_medio) e expõe `periodo`.
-- 2) RPCs para LISTAR / EDITAR (data e rótulo) / APAGAR uma planilha enviada.
-- 3) RPC para PURGAR recomendações pendentes não respondidas (ao subir nova planilha).
-- Run AFTER 017_exact_upload_date.sql
-- =============================================

-- =======  UP  ========

-- ---------------------------------------------
-- 1) Evolução de métricas — corrige fonte do ticket médio (era s.ticket_medio_valor,
--    coluna inexistente, que quebrava a aba "Evolução") e adiciona `periodo` na saída.
--    Precisa de DROP porque o tipo de retorno muda.
-- ---------------------------------------------
DROP FUNCTION IF EXISTS embaplan_portfolio_evolution(TEXT, TEXT);

CREATE OR REPLACE FUNCTION embaplan_portfolio_evolution(
  p_loja TEXT DEFAULT NULL,
  p_produto TEXT DEFAULT NULL
)
RETURNS TABLE(
  batch_id BIGINT,
  rotulo TEXT,
  periodo DATE,
  created_at TIMESTAMPTZ,
  total_anuncios INTEGER,
  receita_total NUMERIC,
  lucro_total NUMERIC,
  investimento_total_ads NUMERIC,
  saude_media NUMERIC,
  acos_medio NUMERIC,
  roas_medio NUMERIC,
  ctr_medio NUMERIC,
  conversao_media NUMERIC,
  ticket_medio_valor NUMERIC
)
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  RETURN QUERY
  SELECT
    b.id AS batch_id,
    b.rotulo,
    b.periodo,
    b.created_at,
    b.total_anuncios,
    COALESCE(SUM(s.receita), 0)::NUMERIC AS receita_total,
    COALESCE(SUM(s.lucro), 0)::NUMERIC AS lucro_total,
    COALESCE(SUM(s.investimento_ads), 0)::NUMERIC AS investimento_total_ads,
    COALESCE(AVG(s.saude), 0)::NUMERIC AS saude_media,
    COALESCE(AVG(s.acos), 0)::NUMERIC AS acos_medio,
    COALESCE(AVG(s.roas), 0)::NUMERIC AS roas_medio,
    COALESCE(AVG(s.ctr), 0)::NUMERIC AS ctr_medio,
    COALESCE(AVG(s.conversao), 0)::NUMERIC AS conversao_media,
    COALESCE(AVG(s.ticket_medio), 0)::NUMERIC AS ticket_medio_valor
  FROM embaplan_upload_batch b
  JOIN embaplan_analysis_snapshot s ON s.batch_id = b.id
  WHERE (p_loja IS NULL OR s.loja = p_loja)
    AND (p_produto IS NULL OR s.produto = p_produto)
  GROUP BY b.id, b.rotulo, b.periodo, b.created_at, b.total_anuncios
  ORDER BY b.created_at ASC;
END;
$$;

GRANT EXECUTE ON FUNCTION embaplan_portfolio_evolution(TEXT, TEXT) TO authenticated;

-- ---------------------------------------------
-- 2) LISTAR planilhas enviadas (1 linha por batch) com contagem de
--    anúncios e de recomendações (total e pendentes), para o painel de gestão.
-- ---------------------------------------------
CREATE OR REPLACE FUNCTION embaplan_list_batches()
RETURNS TABLE(
  batch_id        BIGINT,
  rotulo          TEXT,
  periodo         DATE,
  arquivo_nome    TEXT,
  created_at      TIMESTAMPTZ,
  total_anuncios  INTEGER,
  recs_total      BIGINT,
  recs_pendentes  BIGINT
)
SECURITY DEFINER
SET search_path = public
LANGUAGE sql
STABLE
AS $$
  SELECT
    b.id AS batch_id,
    b.rotulo,
    b.periodo,
    b.arquivo_nome,
    b.created_at,
    b.total_anuncios,
    COUNT(r.id) AS recs_total,
    COUNT(r.id) FILTER (WHERE r.status = 'pendente') AS recs_pendentes
  FROM embaplan_upload_batch b
  LEFT JOIN embaplan_recommendation r ON r.batch_id = b.id
  GROUP BY b.id, b.rotulo, b.periodo, b.arquivo_nome, b.created_at, b.total_anuncios
  ORDER BY b.created_at DESC;
$$;

GRANT EXECUTE ON FUNCTION embaplan_list_batches() TO authenticated;

-- ---------------------------------------------
-- 3) EDITAR uma planilha: trocar a data (periodo) e/ou o rótulo.
--    Parâmetros NULL = não altera aquele campo.
-- ---------------------------------------------
CREATE OR REPLACE FUNCTION embaplan_update_batch(
  p_batch_id BIGINT,
  p_periodo  TEXT DEFAULT NULL,
  p_rotulo   TEXT DEFAULT NULL
)
RETURNS BIGINT
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
  _periodo DATE;
BEGIN
  IF p_batch_id IS NULL THEN
    RAISE EXCEPTION 'p_batch_id é obrigatório.';
  END IF;

  IF p_periodo IS NOT NULL AND TRIM(p_periodo) <> '' THEN
    IF p_periodo ~ '^[0-9]{4}-[0-9]{2}$' THEN
      _periodo := to_date(p_periodo || '-01', 'YYYY-MM-DD');
    ELSIF p_periodo ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN
      _periodo := to_date(p_periodo, 'YYYY-MM-DD');
    ELSE
      _periodo := p_periodo::DATE;
    END IF;
  END IF;

  UPDATE embaplan_upload_batch
  SET
    periodo    = COALESCE(_periodo, periodo),
    rotulo     = COALESCE(NULLIF(TRIM(p_rotulo), ''), rotulo),
    created_at = COALESCE(_periodo::timestamptz, created_at)
  WHERE id = p_batch_id;

  RETURN p_batch_id;
END;
$$;

GRANT EXECUTE ON FUNCTION embaplan_update_batch(BIGINT, TEXT, TEXT) TO authenticated;

-- ---------------------------------------------
-- 4) APAGAR uma planilha: remove o batch (os snapshots caem em cascata).
--    Também remove recomendações pendentes do agente desse batch (lixo);
--    recomendações já tratadas pelo usuário (feito/descartado) são mantidas
--    para histórico, apenas desvinculadas (ON DELETE SET NULL no batch_id).
-- ---------------------------------------------
CREATE OR REPLACE FUNCTION embaplan_delete_batch(
  p_batch_id BIGINT
)
RETURNS INTEGER
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
  _snaps INTEGER;
BEGIN
  IF p_batch_id IS NULL THEN
    RAISE EXCEPTION 'p_batch_id é obrigatório.';
  END IF;

  -- Limpa recomendações pendentes do agente vinculadas a este batch.
  DELETE FROM embaplan_recommendation
  WHERE batch_id = p_batch_id
    AND status = 'pendente'
    AND origem = 'agente';

  SELECT COUNT(*) INTO _snaps
  FROM embaplan_analysis_snapshot
  WHERE batch_id = p_batch_id;

  DELETE FROM embaplan_upload_batch WHERE id = p_batch_id;

  RETURN COALESCE(_snaps, 0);
END;
$$;

GRANT EXECUTE ON FUNCTION embaplan_delete_batch(BIGINT) TO authenticated;

-- ---------------------------------------------
-- 5) PURGAR recomendações pendentes não respondidas.
--    Chamada ao subir uma nova planilha: as sugestões do agente que o
--    usuário não tratou (status='pendente') são apagadas, pois passam a
--    ser baseadas em dados antigos. As marcadas como feito/descartado
--    permanecem (histórico de eficácia). Novas recomendações são geradas
--    sob demanda ("Gerar com IA") já com os dados da nova planilha.
-- ---------------------------------------------
CREATE OR REPLACE FUNCTION embaplan_purge_pending_recommendations(
  p_keep_batch_id BIGINT DEFAULT NULL
)
RETURNS INTEGER
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
  _count INTEGER;
BEGIN
  DELETE FROM embaplan_recommendation
  WHERE status = 'pendente'
    AND origem = 'agente'
    AND (p_keep_batch_id IS NULL OR COALESCE(batch_id, -1) <> p_keep_batch_id);

  GET DIAGNOSTICS _count = ROW_COUNT;
  RETURN _count;
END;
$$;

GRANT EXECUTE ON FUNCTION embaplan_purge_pending_recommendations(BIGINT) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- =======  DOWN  ========
-- DROP FUNCTION IF EXISTS embaplan_purge_pending_recommendations(BIGINT);
-- DROP FUNCTION IF EXISTS embaplan_delete_batch(BIGINT);
-- DROP FUNCTION IF EXISTS embaplan_update_batch(BIGINT, TEXT, TEXT);
-- DROP FUNCTION IF EXISTS embaplan_list_batches();
-- NOTIFY pgrst, 'reload schema';
