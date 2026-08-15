-- ============================================================================
-- 07_SEMANTIC_VIEW.SQL — Semantic View for Quality Analytics & Defect Prediction
-- ============================================================================
USE DATABASE ELECTRONICS_QUALITY;
USE SCHEMA APP;

CREATE OR REPLACE SEMANTIC VIEW APP.ELECTRONICS_QUALITY_ANALYTICS
  COMMENT = 'Electronics Manufacturing quality analytics analytics'
AS
  TABLES (
    CURATED.PERFORMANCE_DASHBOARD AS performance_dashboard,CURATED.TREND_ANALYTICS AS trend_analytics,CURATED.FORECAST_INPUT AS forecast_input,CURATED.OPERATIONAL_RISK AS operational_risk
  );
