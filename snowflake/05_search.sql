-- ============================================================================
-- 05_SEARCH.SQL — Cortex Search for Quality Analytics & Defect Prediction
-- ============================================================================
USE DATABASE ELECTRONICS_QUALITY;
USE SCHEMA SEARCH;

CREATE OR REPLACE CORTEX SEARCH SERVICE SEARCH.ELECTRONICS_QUALITY_SEARCH
  ON CONTENT
  ATTRIBUTES DOC_TYPE, CATEGORY
  WAREHOUSE = ELECTRONICS_WH
  TARGET_LAG = '1 hour'
AS (
  SELECT * FROM RAW.DOCUMENTS
);
