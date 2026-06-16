# PRD-2 — Evolução de Métricas por Upload (Linha do Tempo do Portfólio)

> **Versão:** 1.0 · **Data:** 15/06/2026
> **Depende de:** Épico 1 (snapshots ✅) · PRD-1 (opcional, para enriquecer o contexto)
> **Impacto:** Front-end (dashboard) + n8n

---

## 1. Problema

O usuário sobe a planilha semanalmente, mas **não consegue ver a evolução agregada das métricas** — lucro médio, ACOS médio, ROAS, CTR, ticket médio, saúde média ao longo do tempo. Hoje:

- A **timeline por anúncio** existe (Épico 1) — mas é granular demais para entender a saúde geral do negócio.
- O **dashboard** mostra KPIs do snapshot atual — mas **não mostra tendência** (melhorou ou piorou vs. rodadas anteriores).
- O usuário não sabe se "o lucro subiu ou desceu desde a semana passada" sem contar manualmente.

## 2. Solução

Criar uma **visão de evolução de métricas agregadas** que mostra, para cada upload (rodada), os KPIs do portfólio e a tendência. Disponível no Dashboard como nova aba "📈 Evolução".

## 3. Requisitos Funcionais

### 3.1 — Dados

| RF | Descrição |
|----|-----------|
| RF2.1 | A cada upload, o batch já grava snapshots. A evolução é derivada: para cada `batch_id`, calcular as métricas agregadas (média, soma, distribuição) de todos os anúncios daquele batch. |
| RF2.2 | Métricas agregadas por batch: **Lucro Total**, **Lucro Médio por anúncio**, **ACOS Médio**, **ROAS Médio**, **CTR Médio**, **Conversão Média**, **Ticket Médio**, **Investimento Total Ads**, **Receita Total**, **Nº de Anúncios**, **Saúde Média (0–10)**, **Distribuição de Status** (🚀/⏳/⚠️/🛑). |
| RF2.3 | Cada batch tem `rotulo` (ex.: "Semana 23") e `created_at` — usados como rótulo no eixo X. |

### 3.2 — Visualização

| RF | Descrição |
|----|-----------|
| RF2.4 | Nova aba **"📈 Evolução"** no Dashboard (ao lado de 🏠, 🚨, 🏪, 🎯). |
| RF2.5 | **Gráfico de linhas** mostrando a evolução temporal de até 4 métricas selecionáveis (tabs/chips): Lucro Total, ACOS Médio, ROAS Médio, Ticket Médio. Eixo X = batches (uploads), Eixo Y = valor. |
| RF2.6 | Cada ponto no gráfico exibe: data do upload, valor, e **delta vs. ponto anterior** (ex.: `ACOS: 9.2% → 7.5% (−1.7pp) ✅`). |
| RF2.7 | **Cards de KPI com seta de tendência** — os mesmos KPIs do dashboard atual ganham um indicador: 🟢 ↑ (melhorou vs. último batch), 🔴 ↓ (piorou), 🟡 → (estável, variação < 5%). |
| RF2.8 | **Tabela resumo** abaixo do gráfico: cada linha é um batch, com colunas = métricas, e células coloridas (verde/vermelho) indicando se é melhor ou pior que a média. |
| RF2.9 | **Selector de métricas** — o usuário escolhe qual métrica aparece no gráfico principal (chips clicáveis). Default: Lucro Total. |
| RF2.10 | **Tooltip no gráfico** ao passar o mouse sobre um ponto: exibe todas as métricas daquele batch em um mini-card. |

### 3.3 — Filtros

| RF | Descrição |
|----|-----------|
| RF2.11 | Filtro por **loja** — mostrar evolução de uma loja específica ou de todas. |
| RF2.12 | Filtro por **produto/base** — zoom na evolução de um produto específico. |
| RF2.13 | Filtro por **período** — selecionar range de batches (ex.: "últimas 4 semanas"). |

### 3.4 — Insights Automáticos

| RF | Descrição |
|----|-----------|
| RF2.14 | Abaixo do gráfico, seção **"Insights da Evolução"** com frases geradas automaticamente: |
| RF2.15 | Exemplos de insights: |
|  | - "📈 Lucro subiu 23% nas últimas 4 semanas (de R$ 1.200 para R$ 1.476)." |
|  | - "📉 ACOS médio subiu de 8.1% para 11.3% — investigar campanhas da Base A4." |
|  | - "🎯 Ticket médio manteve estável em R$ 89. Boa consistência." |
|  | - "⚠️ Número de anúncios em 🛑 Ralo aumentou de 2 para 5 nesta semana." |
| RF2.16 | Insights são derivados dos dados (não IA): comparações simples entre batches consecutivos. |

### 3.5 — Comparação entre Rodadas

| RF | Descrição |
|----|-----------|
| RF2.17 | Botão **"Comparar 2 rodadas"** que permite selecionar dois batches e ver lado a lado: métricas, Δ absolutos e Δ percentuais. |
| RF2.18 | Visualização de comparação: tabela com 3 colunas (Métrica | Batch A | Batch B | Δ). |

## 4. Mudanças Técnicas

### n8n

| Componente | Mudança |
|-----------|---------|
| Novo webhook `embaplan-portfolio-evolution` (GET) | Retorna array de objetos `{ batch_id, rotulo, created_at, metricas_agregadas: {...}, distribuicao_status: {...} }`. Ordenado por `created_at` ASC. Aceita query params: `loja`, `produto`, `batch_start`, `batch_end`. |
| Cálculo no webhook | `SELECT` agregado sobre `embaplan_analysis_snapshot` agrupado por `batch_id`. Média, soma e distribuição de status. |

### Banco

| Objeto | Mudança |
|--------|---------|
| **Sem novas tabelas** | Tudo é derivado de `embaplan_analysis_snapshot` + `embaplan_upload_batch` existentes. |
| **Índice opcional** | `CREATE INDEX idx_snapshot_batch_loja ON embaplan_analysis_snapshot(batch_id, loja)` para acelerar a agregação. |

### Front-end (`front.html`)

| Componente | Mudança |
|-----------|---------|
| Nova aba no Dashboard | `renderEvolucao()` — renderiza gráfico SVG simples + cards de KPI com tendência + tabela + insights. |
| Gráfico SVG | Implementação leve (sem Chart.js): linhas SVG com círculos nos pontos, tooltip via div flutuante. ~150 linhas de código. |
| Chips de métricas | Componente reutilizável (já existe padrão no dashboard). |
| Filtros | Selects de loja, produto e período (reutilizar lógica de `renderComparar()`). |

### Prompt do Agente

| Mudança | Detalhe |
|---------|---------|
| Seção "EVOLUÇÃO DO PORTFÓLIO" | "Quando o usuário perguntar sobre tendência, melhoria ou piora de métricas ao longo do tempo, consulte os dados de evolução (via webhook) e responda com os deltas e tendências. Não repita dados que o próprio dashboard já mostra." |

## 5. Fluxo de Dados

```
Upload Planilha
    ↓
n8n: cria batch + snapshots (já existe)
    ↓
n8n: webhook embaplan-portfolio-evolution
    ↓
SELECT batch_id, AVG(lucro), AVG(acos), AVG(roas), ... GROUP BY batch_id
    ↓
Front: renderEvolucao() consome JSON → gráfico + cards + insights
```

## 6. Critérios de Aceite

- [ ] A aba "📈 Evolução" aparece no Dashboard e carrega dados de todos os batches existentes.
- [ ] O gráfico de linhas mostra a métrica selecionável com todos os pontos e deltas.
- [ ] Os cards de KPI mostram a seta de tendência (↑/↓/→) correta comparando com o batch anterior.
- [ ] A tabela resumo lista todos os batches com métricas e cores indicativas.
- [ ] Os insights automáticos refletem os dados reais (não contradizem o gráfico).
- [ ] Filtros por loja/produto/período funcionam e atualizam gráfico + tabela + insights.
- [ ] A comparação entre 2 rodadas mostra Δ absolutos e percentuais corretos.
- [ ] Performance: carregamento da aba em ≤ 2s para até 52 batches (1 ano semanal).

## 7. Estimativa

| Atividade | Horas |
|-----------|-------|
| n8n: webhook `embaplan-portfolio-evolution` | 6h |
| Front: gráfico SVG + lógica de renderização | 10h |
| Front: cards de KPI com tendência + tabela | 6h |
| Front: filtros e comparação | 4h |
| Insights automáticos (lógica de comparação) | 3h |
| Testes e ajustes | 3h |
| **Total** | **32h (~4 dias)** |
