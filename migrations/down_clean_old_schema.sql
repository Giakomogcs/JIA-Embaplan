-- =========================================================================
-- Script Down: Limpeza Geral de Recursos "sameka" do Banco de Dados
-- Use este script no SQL Editor do Supabase antes de rodar as migrations corrigidas.
-- =========================================================================

-- 1. Remoção de triggers e tabelas antigas
DROP TRIGGER IF EXISTS trg_chat_set_user_id ON sameka_chat_message CASCADE;
DROP FUNCTION IF EXISTS trg_set_chat_user_id() CASCADE;
DROP TABLE IF EXISTS sameka_chat_message CASCADE;

-- 2. Remoção de funções CRUD e Admin
DROP FUNCTION IF EXISTS sameka_is_admin() CASCADE;
DROP FUNCTION IF EXISTS sameka_admin_list_users() CASCADE;
DROP FUNCTION IF EXISTS sameka_admin_confirm_user(UUID) CASCADE;
DROP FUNCTION IF EXISTS sameka_admin_update_user(UUID, TEXT) CASCADE;
DROP FUNCTION IF EXISTS sameka_admin_update_user(UUID, TEXT, TEXT) CASCADE;
DROP FUNCTION IF EXISTS sameka_admin_delete_user(UUID) CASCADE;

-- 3. Remoção de funções de Snapshots e Análise
DROP FUNCTION IF EXISTS sameka_embaplan_create_batch(UUID, TEXT, TEXT) CASCADE;
DROP FUNCTION IF EXISTS sameka_embaplan_insert_snapshots(BIGINT, JSONB) CASCADE;
DROP FUNCTION IF EXISTS sameka_embaplan_ad_timeline(TEXT, INTEGER) CASCADE;
DROP FUNCTION IF EXISTS sameka_embaplan_latest_overview(TEXT) CASCADE;
DROP FUNCTION IF EXISTS sameka_embaplan_add_recommendations(BIGINT, UUID, JSONB) CASCADE;
DROP FUNCTION IF EXISTS sameka_embaplan_set_recommendation_status(BIGINT, TEXT, TEXT) CASCADE;
DROP FUNCTION IF EXISTS sameka_embaplan_add_user_change(UUID, TEXT, TEXT, TEXT, TEXT, TEXT) CASCADE;
DROP FUNCTION IF EXISTS sameka_embaplan_evaluate_recommendations(BIGINT, BIGINT) CASCADE;
DROP FUNCTION IF EXISTS sameka_embaplan_recommendations_for_ad(TEXT) CASCADE;
DROP FUNCTION IF EXISTS sameka_embaplan_add_agent_recommendations(UUID, JSONB) CASCADE;
DROP FUNCTION IF EXISTS sameka_embaplan_extract_link(JSONB) CASCADE;
DROP FUNCTION IF EXISTS sameka_embaplan_create_month_batch(UUID, TEXT, TEXT, TEXT, BOOLEAN) CASCADE;
DROP FUNCTION IF EXISTS sameka_embaplan_ad_context_for_ai(TEXT) CASCADE;
DROP FUNCTION IF EXISTS sameka_embaplan_delete_recommendation(BIGINT) CASCADE;

-- 4. Confirmação
NOTIFY pgrst, 'reload schema';
