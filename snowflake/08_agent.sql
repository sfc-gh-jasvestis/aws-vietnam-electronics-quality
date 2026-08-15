-- ============================================================================
-- 08_AGENT.SQL — Cortex Agent for Quality Analytics & Defect Prediction
-- ============================================================================
USE DATABASE ELECTRONICS_QUALITY;
USE SCHEMA APP;

CREATE OR REPLACE CORTEX AGENT APP.ELECTRONICS_QUALITY_AGENT
  COMMENT = 'Quality Analytics & Defect Prediction AI Assistant'
  MODEL = 'claude-opus-4-8'
  TOOLS = (
    SEMANTIC_VIEW_TOOL(SEMANTIC_VIEW => 'ELECTRONICS_QUALITY.APP.ELECTRONICS_QUALITY_ANALYTICS'),    CORTEX_SEARCH_TOOL(CORTEX_SEARCH_SERVICE => 'ELECTRONICS_QUALITY.SEARCH.ELECTRONICS_QUALITY_SEARCH', TOOL_DESCRIPTION => 'Search documents for Electronics Manufacturing information')
  )
  SYSTEM_PROMPT = 'You are the Quality Analytics Agent for Vietnamese electronics manufacturing operations in Ho Chi Minh City & Bac Ninh.';
