# PRD-4 — Tags de Chat (Filtro e Organização de Conversas)

> **Versão:** 1.0 · **Data:** 15/06/2026
> **Depende de:** Nenhuma (independente)
> **Impacto:** Banco + Front-end + n8n

---

## 1. Problema

O usuário tem dezenas de conversas no chat, cada uma sobre um projeto, anúncio ou tema diferente. Hoje:

- A **sidebar** lista conversas por data — sem organização por tema/projeto/anúncio.
- **Não existe como filtrar** chats por assunto ("quero ver a conversa sobre a Base A4 da Shopee").
- **Não existe como marcar** um chat como relevante para um projeto específico.
- O usuário perde tempo scrollando a lista de sessões para encontrar uma conversa anterior.

## 2. Solução

Adicionar um sistema de **tags** às sessões de chat — o usuário pode marcar conversas com tags como `#BaseA4`, `#Shopee`, `#ACOS`, `#Projeto-X`. A sidebar ganha um **campo de filtro por tags** que permite encontrar rapidamente conversas sobre um tema específico.

## 3. Requisitos Funcionais

### 3.1 — Tags na Sessão

| RF | Descrição |
|----|-----------|
| RF4.1 | Cada sessão pode ter **0 a 5 tags** associadas. Tags são strings simples (ex.: "Base A4", "Shopee", "ACOS", "Projeto X", "Lance"). |
| RF4.2 | Tags são **case-insensitive** ("base a4" e "Base A4" são a mesma tag). |
| RF4.3 | Tags são **por usuário** — cada usuário mantém sua própria lista de tags. |
| RF4.4 | O agente pode **sugerir tags automaticamente** ao criar uma nova sessão (baseado no conteúdo da primeira mensagem). Ex.: "Parece que você está falando sobre Base A4 — quer marcar com #BaseA4?". |

### 3.2 — Adicionar/Remover Tags

| RF | Descrição |
|----|-----------|
| RF4.5 | Ao clicar no **ícone de tag** (🏷️) ao lado de um chat na sidebar, abre um mini-popover com: |
|  | - Tags atuais (com botão ✕ para remover) |
|  | - Input de busca de tag existente (autocomplete da lista de tags do usuário) |
|  | - Botão "Criar nova tag" (quando o texto não existe na lista) |
| RF4.6 | Tags também podem ser adicionadas **dentro do chat** — ícone 🏷️ no header do chat atual, ao lado do título. |
| RF4.7 | O agente pode ser instruído a **criar tags automaticamente** quando detectar um tema recorrente: "Quer que eu salve esta conversa com a tag #NovoLance para facilitar encontrar depois?". |
| RF4.8 | Limite de **5 tags por sessão** (evitar spam). |

### 3.3 — Visualização das Tags

| RF | Descrição |
|----|-----------|
| RF4.9 | Na **sidebar**, cada sessão exibe suas tags como **badges coloridos** abaixo do título (ex.: `Base A4` `Shopee`). |
| RF4.10 | Cores das tags são **atribuídas automaticamente** por hash do nome (garante consistência: "Base A4" sempre é azul, "Shopee" sempre é laranja). |
| RF4.11 | Tags com mais de 15 caracteres são truncadas com `...` no badge (tooltip mostra nome completo). |

### 3.4 — Filtro por Tags

| RF | Descrição |
|----|-----------|
| RF4.12 | No topo da sidebar, adicionar **campo de filtro** (ícone 🔍 + input) que filtra sessões por tag. |
| RF4.13 | O filtro é **incremental** — ao digitar, a lista de sessões é filtrada em tempo real. |
| RF4.14 | Suporte a **múltiplas tags no filtro**: digitar `#BaseA4 #Shopee` filtra chats que tenham AMBAS as tags (AND). |
| RF4.15 | Botão "✕" no campo de filtro limpa o filtro e mostra todas as sessões. |
| RF4.16 | O filtro também busca por **texto no título** da sessão (não só tags). |

### 3.5 — Sugestão Automática de Tags

| RF | Descrição |
|----|-----------|
| RF4.17 | Ao criar uma sessão, o sistema analisa a **primeira mensagem** e sugere tags baseadas em: |
|  | - Nomes de lojas detectadas (Shopee, ML, Amazon, Shein) |
|  | - Nomes de produtos/bases mencionados (Base A4, etc.) |
|  | - Palavras-chave de ação (ACOS, lance, orçamento, escala) |
| RF4.18 | A sugestão aparece como **toast notification**: "🏷️ Sugerir tag: #BaseA4 #ACOS" com botões "Aplicar" e "Ignorar". |
| RF4.19 | O usuário pode desativar as sugestões automáticas nas configurações. |

### 3.6 — Tags Globais (Vista de Todas as Tags)

| RF | Descrição |
|----|-----------|
| RF4.20 | No popover de tags, exibir **"Todas as minhas tags"** com contagem: `Base A4 (3)` `Shopee (5)` `ACOS (2)`. |
| RF4.21 | Clicar em uma tag nessa lista **aplica o filtro** na sidebar. |
| RF4.22 | Opção **"Gerenciar tags"** que permite renomear ou deletar uma tag global (renomear afeta todas as sessões). |

## 4. Mudanças Técnicas

### Banco (Nova Migration `015_chat_tags.sql`)

```sql
-- Tabela de tags por sessão
CREATE TABLE IF NOT EXISTS embaplan_chat_tags (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id TEXT NOT NULL,
  user_id UUID NOT NULL REFERENCES embaplan_users(id) ON DELETE CASCADE,
  tag TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(session_id, tag)
);

-- Índices para busca por tag e por sessão
CREATE INDEX idx_chat_tags_tag ON embaplan_chat_tags(tag);
CREATE INDEX idx_chat_tags_session ON embaplan_chat_tags(session_id);
CREATE INDEX idx_chat_tags_user ON embaplan_chat_tags(user_id);

-- RPC: adicionar tag a uma sessão
CREATE OR REPLACE FUNCTION embaplan_chat_add_tag(
  p_session_id TEXT,
  p_tag TEXT
) RETURNS VOID AS $$
BEGIN
  INSERT INTO embaplan_chat_tags (session_id, user_id, tag)
  VALUES (p_session_id, auth.uid(), lower(trim(p_tag)))
  ON CONFLICT (session_id, tag) DO NOTHING;
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
    AND user_id = auth.uid()
    AND tag = lower(trim(p_tag));
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: listar tags de um usuário (com contagem)
CREATE OR REPLACE FUNCTION embaplan_chat_list_user_tags()
RETURNS TABLE(tag TEXT, count BIGINT) AS $$
BEGIN
  RETURN QUERY
  SELECT t.tag, COUNT(*) as count
  FROM embaplan_chat_tags t
  WHERE t.user_id = auth.uid()
  GROUP BY t.tag
  ORDER BY count DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: listar tags de uma sessão
CREATE OR REPLACE FUNCTION embaplan_chat_session_tags(
  p_session_id TEXT
) RETURNS TABLE(tag TEXT) AS $$
BEGIN
  RETURN QUERY
  SELECT t.tag
  FROM embaplan_chat_tags t
  WHERE t.session_id = p_session_id
    AND t.user_id = auth.uid()
  ORDER BY t.tag;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: renomear tag globalmente
CREATE OR REPLACE FUNCTION embaplan_chat_rename_tag(
  p_old_tag TEXT,
  p_new_tag TEXT
) RETURNS VOID AS $$
BEGIN
  UPDATE embaplan_chat_tags
  SET tag = lower(trim(p_new_tag))
  WHERE user_id = auth.uid()
    AND tag = lower(trim(p_old_tag));
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: deletar tag globalmente
CREATE OR REPLACE FUNCTION embaplan_chat_delete_tag(
  p_tag TEXT
) RETURNS VOID AS $$
BEGIN
  DELETE FROM embaplan_chat_tags
  WHERE user_id = auth.uid()
    AND tag = lower(trim(p_tag));
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

### n8n

| Componente | Mudança |
|-----------|---------|
| Novos endpoints | `embaplan-add-tag` (POST: session_id, tag), `embaplan-remove-tag` (POST: session_id, tag), `embaplan-list-tags` (GET), `embaplan-session-tags` (GET: session_id), `embaplan-rename-tag` (POST), `embaplan-delete-tag` (POST). |
| GET sessions | Extender o retorno de `embaplan-chat-get-sessions` para incluir `tags[]` em cada sessão (JOIN com `embaplan_chat_tags`). |

### Front-end (`front.html`)

| Componente | Mudança |
|-----------|---------|
| Sidebar: filtro por tags | Input de busca no topo da `#sessionList` com ícone 🔍. Filtra por tag e/ou texto do título. ~60 linhas JS. |
| Sidebar: badges de tags | Em cada `.session-item`, adicionar container de badges abaixo do título. ~20 linhas CSS + JS. |
| Popover de tags | Componente flutuante ao clicar no ícone 🏷️ de uma sessão. Input + autocomplete + lista de tags atuais. ~120 linhas HTML/JS/CSS. |
| Toast de sugestão | Notificação toast com sugestão de tags automáticas. ~40 linhas. |
| Header do chat: ícone 🏷️ | Botão no header que abre o popover de tags da sessão atual. ~15 linhas. |
| Gerenciar tags | Modal simples com lista de todas as tags, rename, delete. ~80 linhas. |

### Prompt do Agente

| Mudança | Detalhe |
|---------|---------|
| Seção "TAGS DA SESSÃO" | Injetar no prompt as tags atuais da sessão: "Esta conversa está marcada com: #BaseA4, #ACOS. Use isso para contextualizar suas respostas." |
| Sugestão de tags | Quando o agente detectar um tema recorrente, sugerir: "Quer marcar esta conversa com #Tag para facilitar encontrar depois?" |

## 5. Fluxo de Dados

```
Usuário clica 🏷️ na sidebar
    ↓
Popover abre (GET embaplan-session-tags)
    ↓
Usuário seleciona/cria tag
    ↓
POST embaplan-add-tag (session_id, tag)
    ↓
Tag salva em embaplan_chat_tags
    ↓
Sidebar re-renderiza com badge da tag
    ↓
Filtro: digitar "Base A4" filtra sessões com essa tag
```

## 6. Critérios de Aceite

- [ ] Tags podem ser adicionadas/removidas de qualquer sessão via popover.
- [ ] Tags aparecem como badges coloridos na sidebar, abaixo do título.
- [ ] Campo de filtro filtra sessões por tag em tempo real.
- [ ] Filtro com múltiplas tags (AND) funciona: `#BaseA4 #Shopee`.
- [ ] Tags são case-insensitive e limitadas a 5 por sessão.
- [ ] Sugestão automática de tags aparece na primeira mensagem (toast).
- [ ] "Todas as minhas tags" mostra contagem correta.
- [ ] Renomear/deletar tag afeta todas as sessões daquele usuário.
- [ ] Tags persistem entre sessões (reload da página mantém as tags).

## 7. Estimativa

| Atividade | Horas |
|-----------|-------|
| Migration SQL + RPCs | 4h |
| n8n: endpoints de tags | 4h |
| Front: sidebar filtro + badges | 6h |
| Front: popover de tags | 6h |
| Front: toast de sugestão + gerenciar tags | 4h |
| Integração com prompt do agente | 2h |
| Testes | 2h |
| **Total** | **28h (~3.5 dias)** |
