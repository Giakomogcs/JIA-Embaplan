-- =============================================
-- Embaplan — 019: Cronologia por PERÍODO (mês real da planilha)
-- Problema: tudo ordenava por created_at (hora do upload). Subir uma
-- planilha de um mês passado a colocava como "mais atual". Agora a
-- ordem cronológica segue o `periodo` escolhido no calendário, com
-- created_at apenas como desempate.
-- Afeta: create_month_batch, latest_overview, ad_timeline,
--        ad_context_for_ai, add_agent_recommendations.
-- Run AFTER 018_batch_management.sql
-- =============================================

-- =======  UP  ========

-- ---------------------------------------------
-- 1) Upload: gravar created_at = periodo, para que a ordenação por
--    data fique consistente mesmo onde ainda se use created_at.
-- ---------------------------------------------
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

  -- created_at recebe o período (à meia-noite) para manter a cronologia
  -- coerente com a data escolhida no calendário, não a hora do upload.
  INSERT INTO embaplan_upload_batch (user_id, rotulo, arquivo_nome, periodo, created_at)
  VALUES (p_user_id, _rotulo, p_arquivo_nome, _periodo, _periodo::timestamptz)
  RETURNING id INTO _batch_id;

  RETURN _batch_id;
END;
$$;

GRANT EXECUTE ON FUNCTION embaplan_create_month_batch(UUID, TEXT, TEXT, TEXT, BOOLEAN) TO authenticated;

-- ---------------------------------------------
-- 2) Dashboard (estado atual): "mais recente" = maior período.
-- ---------------------------------------------
DROP FUNCTION IF EXISTS embaplan_latest_overview(TEXT);

CREATE OR REPLACE FUNCTION embaplan_latest_overview(
  p_loja TEXT DEFAULT NULL
)
RETURNS TABLE(
  anuncio_indice  TEXT,
  loja            TEXT,
  produto         TEXT,
  titulo          TEXT,
  status          TEXT,
  saude           NUMERIC,
  acos            NUMERIC,
  roas            NUMERIC,
  lucro           NUMERIC,
  receita         NUMERIC,
  ticket_medio    NUMERIC,
  delta_saude     NUMERIC,
  delta_lucro     NUMERIC,
  delta_acos      NUMERIC,
  tendencia       TEXT
)
SECURITY DEFINER
SET search_path = public
LANGUAGE sql
STABLE
AS $$
  WITH ranked AS (
    SELECT
      s.*,
      ROW_NUMBER() OVER (
        PARTITION BY s.anuncio_indice
        ORDER BY COALESCE(b.periodo, b.created_at::date) DESC, b.created_at DESC
      ) AS rn,
      LEAD(s.saude) OVER (
        PARTITION BY s.anuncio_indice
        ORDER BY COALESCE(b.periodo, b.created_at::date) DESC, b.created_at DESC
      ) AS prev_saude,
      LEAD(s.lucro) OVER (
        PARTITION BY s.anuncio_indice
        ORDER BY COALESCE(b.periodo, b.created_at::date) DESC, b.created_at DESC
      ) AS prev_lucro,
      LEAD(s.acos) OVER (
        PARTITION BY s.anuncio_indice
        ORDER BY COALESCE(b.periodo, b.created_at::date) DESC, b.created_at DESC
      ) AS prev_acos
    FROM embaplan_analysis_snapshot s
    JOIN embaplan_upload_batch b ON b.id = s.batch_id
    WHERE p_loja IS NULL OR s.loja = p_loja
  )
  SELECT
    anuncio_indice, loja, produto, titulo, status,
    saude, acos, roas, lucro, receita, ticket_medio,
    (saude - prev_saude) AS delta_saude,
    (lucro - prev_lucro) AS delta_lucro,
    (acos  - prev_acos)  AS delta_acos,
    CASE
      WHEN prev_saude IS NULL THEN 'novo'
      WHEN (saude - prev_saude) >= 0.5 OR (lucro - prev_lucro) > 0 THEN 'evoluindo'
      WHEN (saude - prev_saude) <= -0.5 OR (lucro - prev_lucro) < 0 THEN 'piorando'
      ELSE 'estavel'
    END AS tendencia
  FROM ranked
  WHERE rn = 1
  ORDER BY receita DESC NULLS LAST;
$$;

GRANT EXECUTE ON FUNCTION embaplan_latest_overview(TEXT) TO authenticated;

-- ---------------------------------------------
-- 3) Linha do tempo de um anúncio: ordena por período.
-- ---------------------------------------------
DROP FUNCTION IF EXISTS embaplan_ad_timeline(TEXT, INTEGER);

CREATE OR REPLACE FUNCTION embaplan_ad_timeline(
  p_anuncio_indice TEXT,
  p_limit          INTEGER DEFAULT 24
)
RETURNS TABLE(
  batch_id         BIGINT,
  rotulo           TEXT,
  data_upload      TIMESTAMPTZ,
  versao           BIGINT,
  loja             TEXT,
  produto          TEXT,
  titulo           TEXT,
  status           TEXT,
  saude            NUMERIC,
  acos             NUMERIC,
  roas             NUMERIC,
  conversao        NUMERIC,
  ctr              NUMERIC,
  lucro            NUMERIC,
  receita          NUMERIC,
  vendas           NUMERIC,
  ticket_medio     NUMERIC,
  delta_saude      NUMERIC,
  delta_lucro      NUMERIC,
  delta_acos       NUMERIC,
  tendencia        TEXT
)
SECURITY DEFINER
SET search_path = public
LANGUAGE sql
STABLE
AS $$
  WITH serie AS (
    SELECT
      s.batch_id,
      b.rotulo,
      COALESCE(b.periodo::timestamptz, b.created_at) AS data_upload,
      ROW_NUMBER() OVER (
        ORDER BY COALESCE(b.periodo, b.created_at::date), b.created_at
      ) AS versao,
      s.loja, s.produto, s.titulo, s.status,
      s.saude, s.acos, s.roas, s.conversao, s.ctr,
      s.lucro, s.receita, s.vendas, s.ticket_medio,
      LAG(s.saude) OVER (
        ORDER BY COALESCE(b.periodo, b.created_at::date), b.created_at
      ) AS prev_saude,
      LAG(s.lucro) OVER (
        ORDER BY COALESCE(b.periodo, b.created_at::date), b.created_at
      ) AS prev_lucro,
      LAG(s.acos) OVER (
        ORDER BY COALESCE(b.periodo, b.created_at::date), b.created_at
      ) AS prev_acos
    FROM embaplan_analysis_snapshot s
    JOIN embaplan_upload_batch b ON b.id = s.batch_id
    WHERE s.anuncio_indice = p_anuncio_indice
  )
  SELECT
    batch_id, rotulo, data_upload, versao,
    loja, produto, titulo, status,
    saude, acos, roas, conversao, ctr,
    lucro, receita, vendas, ticket_medio,
    (saude - prev_saude) AS delta_saude,
    (lucro - prev_lucro) AS delta_lucro,
    (acos  - prev_acos)  AS delta_acos,
    CASE
      WHEN prev_saude IS NULL THEN 'novo'
      WHEN (saude - prev_saude) >= 0.5 OR (lucro - prev_lucro) > 0 THEN 'evoluindo'
      WHEN (saude - prev_saude) <= -0.5 OR (lucro - prev_lucro) < 0 THEN 'piorando'
      ELSE 'estavel'
    END AS tendencia
  FROM serie
  ORDER BY data_upload
  LIMIT p_limit;
$$;

GRANT EXECUTE ON FUNCTION embaplan_ad_timeline(TEXT, INTEGER) TO authenticated;

-- ---------------------------------------------
-- 4) Contexto da IA: "atual" e "histórico" por período.
--    DROP necessário apenas se assinatura mudar; aqui mantém-se igual,
--    então CREATE OR REPLACE basta.
-- ---------------------------------------------
DROP FUNCTION IF EXISTS embaplan_ad_context_for_ai(TEXT);

CREATE OR REPLACE FUNCTION embaplan_ad_context_for_ai(
  p_anuncio_indice TEXT
)
RETURNS JSONB
SECURITY DEFINER
SET search_path = public
LANGUAGE sql
STABLE
AS $$
  WITH atual AS (
    SELECT s.*
    FROM embaplan_analysis_snapshot s
    JOIN embaplan_upload_batch b ON b.id = s.batch_id
    WHERE s.anuncio_indice = p_anuncio_indice
    ORDER BY COALESCE(b.periodo, b.created_at::date) DESC, b.created_at DESC
    LIMIT 1
  ),
  hist AS (
    SELECT *
    FROM (
      SELECT s.*, COALESCE(b.periodo, b.created_at::date) AS _ord
      FROM embaplan_analysis_snapshot s
      JOIN embaplan_upload_batch b ON b.id = s.batch_id
      WHERE s.anuncio_indice = p_anuncio_indice
      ORDER BY COALESCE(b.periodo, b.created_at::date) DESC, b.created_at DESC
      LIMIT 6
    ) h
    ORDER BY h._ord ASC, h.created_at ASC
  )
  SELECT jsonb_build_object(
    'anuncio_indice', p_anuncio_indice,
    'encontrado', (SELECT COUNT(*) FROM atual) > 0,
    'atual', (
      SELECT jsonb_build_object(
        'loja', a.loja,
        'produto', a.produto,
        'titulo', a.titulo,
        'status', a.status,
        'saude', a.saude,
        'vendas', a.vendas,
        'receita', a.receita,
        'lucro', a.lucro,
        'investimento_ads', a.investimento_ads,
        'acos', a.acos,
        'ctr', a.ctr,
        'conversao', a.conversao,
        'roas', a.roas,
        'roi', a.roi,
        'margem_liquida', a.margem_liquida,
        'ticket_medio', a.ticket_medio,
        'link', a.metrics_jsonb->>'link',
        'batch_id', a.batch_id,
        'data', a.created_at
      )
      FROM atual a
    ),
    'historico', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'data', h.created_at,
        'saude', h.saude,
        'acos', h.acos,
        'roas', h.roas,
        'conversao', h.conversao,
        'ctr', h.ctr,
        'lucro', h.lucro,
        'receita', h.receita,
        'status', h.status
      ))
      FROM hist h
    ), '[]'::jsonb),
    'recomendacoes_existentes', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'texto', r.texto,
        'origem', r.origem,
        'status', r.status,
        'metrica_alvo', r.metrica_alvo,
        'resultado', r.resultado
      ) ORDER BY r.created_at DESC)
      FROM embaplan_recommendation r
      WHERE r.anuncio_indice = p_anuncio_indice
    ), '[]'::jsonb)
  );
$$;

GRANT EXECUTE ON FUNCTION embaplan_ad_context_for_ai(TEXT) TO authenticated;

-- ---------------------------------------------
-- 5) Recomendações do agente: ancorar no batch de MAIOR período.
-- ---------------------------------------------
DROP FUNCTION IF EXISTS embaplan_add_agent_recommendations(UUID, JSONB);

CREATE OR REPLACE FUNCTION embaplan_add_agent_recommendations(
  p_user_id UUID,
  p_rows    JSONB
)
RETURNS INTEGER
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
  _count   INTEGER := 0;
  _r       JSONB;
  _indice  TEXT;
  _texto   TEXT;
  _batch   BIGINT;
  _snap    BIGINT;
BEGIN
  IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' THEN
    RAISE EXCEPTION 'p_rows deve ser um array JSON.';
  END IF;

  FOR _r IN SELECT * FROM jsonb_array_elements(p_rows)
  LOOP
    _indice := COALESCE(_r->>'anuncio_indice', _r->>'indice');
    _texto  := _r->>'texto';
    CONTINUE WHEN _indice IS NULL OR COALESCE(_texto, '') = '';

    -- batch + snapshot do MAIOR período deste anúncio
    SELECT s.batch_id, s.id INTO _batch, _snap
    FROM embaplan_analysis_snapshot s
    JOIN embaplan_upload_batch b ON b.id = s.batch_id
    WHERE s.anuncio_indice = _indice
    ORDER BY COALESCE(b.periodo, b.created_at::date) DESC, b.created_at DESC
    LIMIT 1;

    IF EXISTS (
      SELECT 1 FROM embaplan_recommendation
      WHERE anuncio_indice = _indice
        AND texto = _texto
        AND origem = 'agente'
        AND COALESCE(batch_id, -1) = COALESCE(_batch, -1)
    ) THEN
      CONTINUE;
    END IF;

    INSERT INTO embaplan_recommendation (
      batch_id, snapshot_id, user_id, loja, produto, anuncio_indice,
      origem, texto, prioridade, metrica_alvo
    )
    VALUES (
      _batch, _snap, p_user_id, _r->>'loja', _r->>'produto', _indice,
      'agente', _texto,
      COALESCE(NULLIF(_r->>'prioridade', '')::INTEGER, 0),
      _r->>'metrica_alvo'
    );

    _count := _count + 1;
  END LOOP;

  RETURN _count;
END;
$$;

GRANT EXECUTE ON FUNCTION embaplan_add_agent_recommendations(UUID, JSONB) TO authenticated;

-- ---------------------------------------------
-- 6) Evolução do portfólio: ordena a linha do tempo por período
--    (robusto para batches antigos cujo created_at != periodo).
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
  ORDER BY COALESCE(b.periodo, b.created_at::date) ASC, b.created_at ASC;
END;
$$;

GRANT EXECUTE ON FUNCTION embaplan_portfolio_evolution(TEXT, TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- =======  DOWN  ========
-- Reverter para a ordenação por created_at exige reaplicar as versões
-- anteriores das funções (008, 010, 014, 017). Sem DROP destrutivo aqui.
