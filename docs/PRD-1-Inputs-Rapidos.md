# PRD-1 — Inputs Rápidos com Contexto

> **Versão:** 1.0 · **Data:** 15/06/2026
> **Depende de:** Nenhuma (independente)
> **Impacto:** Front-end + prompt do agente

---

## 1. Problema

O usuário precisa fornecer contexto manualmente toda vez que quer analisar algo específico ("quero analisar a campanha X da loja Y", "qual o impacto de mudar o lance da campanha Z"). Isso é:

- **Lento** — digitar tudo a cada interação
- **Inconsistente** — às vezes esquece de mencionar a loja, a campanha ou o período
- **Frustrante** — o agente pergunta de volta ("qual loja?", "qual campanha?"), quebrando o fluxo

## 2. Solução

Criar um **fluxo de inputs rápidos** — um modal/overlay que aparece antes de enviar a mensagem ao agente, com perguntas guiadas que capturam o contexto necessário de forma estruturada. Perguntas opcionais só aparecem quando o contexto exige (ex.: "qual campanha?").

## 3. Requisitos Funcionais

### 3.1 — Trigger: quando aparece

| RF | Descrição |
|----|-----------|
| RF1.1 | Ao clicar no botão "Analisar" (novo botão no chat, ao lado de "Enviar"), o modal de inputs rápidos abre. |
| RF1.2 | Se o usuário digitar uma mensagem normal e enviar (Enter/botão Enviar), **não** abre o modal — vai direto ao agente como hoje. |
| RF1.3 | O modal pode ser chamado também pelo Dashboard (botão "🔍 Analisar" em qualquer card de anúncio), pré-preenchendo os campos disponíveis. |

### 3.2 — Campos do modal (por categoria)

| Campo | Tipo | Obrigatório | Descrição |
|-------|------|-------------|-----------|
| **Loja** | Select (multi) | Sim | Lista das lojas detectadas na última planilha (ex.: Shopee, ML, Amazon). Default: "Todas". |
| **Campanha / Anúncio** | Buscador (autocomplete) | Não | Busca por nome do produto, título do anúncio ou índice (`L2#47`). Se vazio, analisa todos. |
| **Produto / Base** | Buscador (autocomplete) | Não | Filtrar por produto específico (ex.: "Base A4"). |
| **Foco da Análise** | Chips selecionáveis | Sim (1+*) | Opções: `📊 Performance Geral` · `💰 Lucro / Margem` · `📉 ACOS / CTR` · `🚀 Oportunidade de Escala` · `🛑 Problemas / Ralo` · `🏷️ Comparar Lojas`. Default: Performance Geral. *Múltipla seleção.* |
| **Observações Livres** | Textarea (2 linhas) | Não | Campo aberto para detalhar (ex.: "quero saber se posso aumentar verba da campanha X sem perder margem"). |

### 3.3 — Comportamento

| RF | Descrição |
|----|-----------|
| RF1.4 | O modal pré-preenche automaticamente os campos quando chamado a partir de um card no Dashboard (ex.: card do anúncio "Base A4 — Shopee" → Loja=Shopee, Produto=Base A4). |
| RF1.5 | Ao confirmar, o modal monta uma **mensagem estruturada** no formato `[LOJA: Shopee] [PRODUTO: Base A4] [FOCO: Lucro/Margem] [OBS: quero saber se posso aumentar verba]` e envia ao agente. |
| RF1.6 | O agente (prompt n8n) recebe o contexto estruturado e **não precisa perguntar de volta** — já tem loja, produto e foco. |
| RF1.7 | Botão "Fechar" no modal cancela a ação e volta ao chat. |
| RF1.8 | Os campos "Campanha" e "Produto" populam com dados reais do último `SUMARIO_PRE_CALCULADO` (via n8n, chamada ao sub-fluxo ao abrir o modal). |

### 3.4 — UX

| RF | Descrição |
|----|-----------|
| RF1.9 | Modal com design consistente com o Embaplan (cores primary, fundo `bg-message-assistant`). |
| RF1.10 | Animação de entrada (slide-up ou fade-in, ≤200ms). |
| RF1.11 | Se o usuário já tem um chat aberto, os campos "Loja" e "Produto" pré-preenchem com base nas últimas mensagens detectadas (heurística simples). |

## 4. Mudanças Técnicas

### Front-end (`front.html`)

- Novo botão "🔍 Analisar" no `#inputArea` (ao lado de "Enviar").
- Novo componente `<div id="quickInputModal">` com:
  - Select de lojas (populado via chamada ao webhook `embaplan-dashboard` para obter lojas disponíveis).
  - Buscador de campanhas/produtos (autocomplete com debounce).
  - Chips de foco da análise (toggle multi-select).
  - Textarea de observações.
  - Botões "Confirmar" e "Cancelar".
- Função `showQuickInputModal(defaults?)` — abre o modal com pré-preenchimento opcional.
- Função `buildStructuredPrompt(fields)` — monta a string `[LOJA:...] [PRODUTO:...]...`.
- Modificação em `handleSendMessage()` — intercepta a mensagem formatada e envia ao agente.

### n8n

- **Opcional:** novo endpoint `embaplan-autocomplete?q=...` para buscar nomes de campanhas/produtos do último sumário. Alternativa: já usar o `embaplan-dashboard` existente (retorna a lista de anúncios).

### Prompt do Agente

- Adicionar regra: "Quando receber contexto estruturado `[LOJA:...] [PRODUTO:...] [FOCO:...]`, **não peça confirmação** — analise direto o escopo informado."

### Banco

- **Sem novas tabelas.**

## 5. Critérios de Aceite

- [ ] O modal abre ao clicar "Analisar" e pré-popula com dados reais da última planilha.
- [ ] Selecionar loja + produto + foco gera uma mensagem estruturada correta.
- [ ] O agente responde sem pedir confirmação de loja/produto quando o contexto vem estruturado.
- [ ] Chamado a partir de um card do Dashboard, os campos vêm pré-preenchidos.
- [ ] Fechar o modal cancela sem enviar nada.

## 6. Estimativa

| Atividade | Horas |
|-----------|-------|
| Front-end: modal + lógica | 8h |
| Integração com dados reais (autocomplete) | 4h |
| Testes de UX | 2h |
| **Total** | **14h (~2 dias)** |
