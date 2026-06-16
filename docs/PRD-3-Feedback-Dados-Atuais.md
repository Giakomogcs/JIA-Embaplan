# PRD-3 — Feedback com Dados Atuais (Comparação com a Planilha Recente)

> **Versão:** 1.0 · **Data:** 15/06/2026
> **Depende de:** PRD-2 (Evolução de Métricas) + snapshots existentes
> **Impacto:** Front-end (cards) + prompt do agente

---

## 1. Problema

Quando o usuário pergunta "por que o ACOS subiu?" ou "o preço mudou?", o agente hoje não tem como **usar os dados atuais da planilha** como referência para comparar com o snapshot anterior. Ele apenas mostra os números do snapshot, sem correlacionar:

- "O preço do produto X subiu de R$ 45 para R$ 52 → isso impactou o ticket médio e o ACOS."
- "O investimento na campanha Y dobrou → o lucro subiu mas o ACOS subiu também."
- "O CTR caiu mas a conversão subiu → possível mudança de público-alvo."

O usuário precisa de um **feedback inteligente** que cruze os dados atuais da planilha com o histórico para **entender o que aconteceu**.

## 2. Solução

Ao analisar a planilha (após upload ou ao responder perguntas), o agente **compara os dados atuais com o último snapshot** e gera um resumo de alterações detectadas. Isso é usado como contexto adicional nas respostas.

## 3. Requisitos Funcionais

### 3.1 — Deteção de Alterações

| RF | Descrição |
|----|-----------|
| RF3.1 | Ao processar uma nova planilha, o sistema compara **campo a campo** do `SUMARIO_PRE_CALCULADO` atual com o snapshot anterior (batch mais recente). |
| RF3.2 | São detectadas alterações em: **Preço** (unitário), **Investimento Ads** (diário/mensal), **Orçamento**, **Lance** (se disponível), **Nº de anúncios** (novo/removido), **Status** (🚀→🛑, etc.). |
| RF3.3 | A comparação é **por anúncio** (chave: `loja + produto + anuncio_indice`) — assim identifica mudanças em campanhas específicas. |
| RF3.4 | Apenas diferenças acima de um threshold são reportadas (ex.: preço variou > 2%, investimento variou > 10%). Evitar ruído. |

### 3.2 — Exibição no Dashboard

| RF | Descrição |
|----|-----------|
| RF3.5 | Na aba **"📈 Evolução"** (PRD-2), adicionar seção **"🔄 Alterações Detectadas"** que lista, na ordem de impacto: |
|  | - "Preço de Base A4 subiu de R$ 45 → R$ 52 (+15.6%) → ticket médio impactado" |
|  | - "Investimento da campanha X aumentou de R$ 50 → R$ 80 (+60%) → lucro +R$ 120" |
|  | - "Anúncio novo detectado: Base A4 (loja Y) — ainda sem histórico" |
|  | - "Anúncio removido: Base X (loja Z) — existia no último upload" |
| RF3.6 | Cada linha de alteração tem ícone: 🔴 Preço · 💰 Investimento · 📊 Métrica · ➕ Novo · ➖ Removido · ⚙️ Config. |
| RF3.7 | Se não houver alterações significativas, exibir: "✅ Nenhuma alteração relevante detectada desde o último upload." |

### 3.3 — Exibição nos Cards de Anúncio (Chat)

| RF | Descrição |
|----|-----------|
| RF3.8 | No card de cada anúncio (tanto no chat quanto no dashboard), ao lado do status, adicionar badge **"Alterado"** se houve mudança significativa vs. o snapshot anterior. |
| RF3.9 | Clicar no badge "Alterado" expande mini-painel com as alterações daquele anúncio específico. |
| RF3.10 | No chat, quando o agente analisa um anúncio, ele deve mencionar: "Detectei alterações desde a última análise: [lista]." |

### 3.4 — Contexto para o Agente

| RF | Descrição |
|----|-----------|
| RF3.11 | O `SUMARIO_PRE_CALCULADO` já é enviado ao agente. Adicionar ao prompt uma seção **"ALTERAÇÕES DESDE O ÚLTIMO UPLOAD"** que lista as diferenças detectadas (campo, valor anterior, valor atual, delta %). |
| RF3.12 | O agente, ao recomendar, **usa as alterações como hipótese**: "O ACOS subiu porque o investimento aumentou 60% mas a receita só subiu 20% — possível saturação." |
| RF3.13 | O agente **não inventa causas** — só correlaciona dados que existem na comparação. Se não há mudança no preço, não diz que "o preço subiu". |

### 3.5 — Preço e Detalhes Operacionais

| RF | Descrição |
|----|-----------|
| RF3.14 | Se a planilha contém coluna de **preço unitário**, comparar e reportar variação. |
| RF3.15 | Se a planilha contém **nome do produto/campanha alterado**, detectar e reportar (possível rebranding). |
| RF3.16 | Se a planilha contém **URL/link do anúncio alterado**, detectar e reportar (possível recriação do anúncio). |

## 4. Mudanças Técnicas

### n8n

| Componente | Mudança |
|-----------|---------|
| Sub-fluxo de captura (upload) | Após gerar `SUMARIO_PRE_CALCULADO`, executar `GET embaplan-ad-timeline?loja=X&produto=Y&indice=Z` para o anúncio mais recente e comparar com os campos atuais. |
| Novo webhook `embaplan-detect-changes` (POST) | Recebe `SUMARIO_PRE_CALCULADO` atual + `batch_id_anterior`. Retorna `{ alteracoes: [...], resumo: "3 alterações detectadas" }`. Cada alteração: `{ anuncio, campo, valor_anterior, valor_atual, delta_pct, tipo }`. |
| Prompt do agente | Adicionar seção "ALTERAÇÕES DESDE O ÚLTIMO UPLOAD" que é injetada automaticamente pelo n8n antes de cada análise. |

### Banco

| Objeto | Mudança |
|--------|---------|
| **Sem novas tabelas** | Alterações são calculadas em tempo real a partir de snapshots existentes + dados atuais. |
| **Opcional** | Se quiser persistir as alterações detectadas: tabela `embaplan_detected_changes` com `(id, batch_id_novo, batch_id_anterior, alteracoes_jsonb)`. Útil para não recalcular toda vez. |

### Front-end (`front.html`)

| Componente | Mudança |
|-----------|---------|
| Seção "🔄 Alterações Detectadas" na aba Evolução | Lista de alterações com ícones e deltas. ~80 linhas HTML/JS. |
| Badge "Alterado" nos cards | Mini-badge ao lado do status. Clique expande detalhes. ~30 linhas CSS + JS. |
| Contexto no chat | Quando o agente responde sobre um anúncio, renderiza mini-box de alterações antes do diagnóstico. |

### Prompt do Agente

```markdown
## ALTERAÇÕES DESDE O ÚLTIMO UPLOAD
Quando houver alterações detectadas (preço, investimento, configurações),
use-as como HIPÓTESE principal para explicar variações de métricas.

Regras:
1. SEMPRE cite os dados concretos ("preço subiu de R$ 45 para R$ 52")
2. NUNCA invente causas que não estejam nos dados
3. Se não houver alteração detectada, diga "as configurações mantiveram-se
   estáveis — a variação pode estar em fatores externos (sazonalidade,
   concorrência)"
4. Correlacione: "investimento +60% + receita +20% = margem comprimida"
```

## 5. Fluxo de Dados

```
Upload Planilha
    ↓
n8n: SUMARIO_PRE_CALCULADO (dados atuais)
    ↓
n8n: GET embaplan-ad-timeline → último snapshot anterior
    ↓
n8n: Comparar campo a campo (threshold > 2%/10%)
    ↓
Front: render Alterações Detectadas (dashboard)
    ↓
n8n: Injetar ALTERAÇÕES no prompt do agente
    ↓
Agente: recomendar usando alterações como hipótese
```

## 6. Critérios de Aceite

- [ ] Ao subir uma nova planilha, o dashboard mostra as alterações detectadas vs. o upload anterior.
- [ ] Alterações de preço, investimento e configurações são detectadas corretamente com delta %.
- [ ] O badge "Alterado" aparece nos cards de anúncios que tiveram mudanças.
- [ ] Clicar no badge expande os detalhes das alterações.
- [ ] O agente menciona as alterações ao analisar um anúncio modificado.
- [ ] O agente não inventa causas não suportadas pelos dados.
- [ ] Se não houver alterações, a mensagem "Nenhuma alteração relevante" aparece.
- [ ] Thresholds de detecção evitam ruído (variações < 2% não são reportadas).

## 7. Estimativa

| Atividade | Horas |
|-----------|-------|
| n8n: webhook `embaplan-detect-changes` | 6h |
| n8n: integração com upload (injetar alterações no prompt) | 4h |
| Front: seção "Alterações Detectadas" no dashboard | 6h |
| Front: badge "Alterado" nos cards | 4h |
| Testes de detecção com dados reais | 3h |
| **Total** | **23h (~3 dias)** |
