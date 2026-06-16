-- Migration 016: Portfolio Evolution — Agregação histórica de métricas por batch
-- Data: 16/06/2026
-- PRD: PRD-2-Evolucao-Metricas.md

CREATE OR REPLACE FUNCTION embaplan_portfolio_evolution(
  p_loja TEXT DEFAULT NULL,
  p_produto TEXT DEFAULT NULL
)
RETURNS TABLE(
  batch_id BIGINT,
  rotulo TEXT,
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
    COALESCE(AVG(s.ticket_medio_valor), 0)::NUMERIC AS ticket_medio_valor
  FROM embaplan_upload_batch b
  JOIN embaplan_analysis_snapshot s ON s.batch_id = b.id
  WHERE (p_loja IS NULL OR s.loja = p_loja)
    AND (p_produto IS NULL OR s.produto = p_produto)
  GROUP BY b.id, b.rotulo, b.created_at, b.total_anuncios
  ORDER BY b.created_at ASC;
END;
$$;

GRANT EXECUTE ON FUNCTION embaplan_portfolio_evolution(TEXT, TEXT) TO authenticated;
NOTIFY pgrst, 'reload schema';
