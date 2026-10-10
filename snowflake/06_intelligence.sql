-- ============================================================================
-- 06_INTELLIGENCE.SQL - search, anomaly detection, semantic view, agent,
-- live-telemetry alert and on-demand refresh DAG.
-- Run with snowflake/run_intelligence.py (substitutes checked __DEMO_DB__ /
-- __DEMO_WH__ / __ALERT_EMAIL__). Requires 00-05, plus 08 (Snowflake only) or
-- aws/setup_aws.py (AWS build) for RAW.LIVE_TELEMETRY.
-- Alerts and tasks are created SUSPENDED; run them with EXECUTE ALERT / EXECUTE TASK.
-- ============================================================================
USE DATABASE __DEMO_DB__;
CREATE SCHEMA IF NOT EXISTS SEARCH;
CREATE SCHEMA IF NOT EXISTS APP;

-- ---------- Synthetic quality-hold SOP corpus (clearly synthetic SOPs) ----------
CREATE OR REPLACE TABLE SEARCH.PROCESS_DOCS AS
WITH causes AS (
  SELECT DISTINCT r.ROOT_CAUSE, l.CATEGORY
  FROM RAW.LINE_DAILY r JOIN RAW.LINES l ON l.ID = r.ENTITY_ID
  WHERE r.ROOT_CAUSE IS NOT NULL AND r.HOLD_COUNT > 0
)
SELECT
  'SOP-' || LPAD(ROW_NUMBER() OVER (ORDER BY CATEGORY, ROOT_CAUSE)::VARCHAR, 3, '0') AS DOC_ID,
  'SOP' AS DOC_TYPE,
  CATEGORY,
  ROOT_CAUSE,
  CATEGORY || ' - ' || ROOT_CAUSE || ' hold response' AS TITLE,
  'Synthetic demo SOP. Process stage: ' || CATEGORY || '. Hold cause: ' || ROOT_CAUSE || '. '
  || 'Step 1: place the affected board lot on quality hold, quarantine work in progress and notify the shift quality engineer. '
  || 'Step 2: ' || CASE
       WHEN ROOT_CAUSE ILIKE '%paste volume%' OR ROOT_CAUSE ILIKE '%print offset%' THEN 'review solder paste inspection results for the lot, check stencil alignment, print pressure and paste age, and reprint a first article before restarting.'
       WHEN ROOT_CAUSE ILIKE '%stencil%' THEN 'clean the stencil apertures, check the under-stencil wipe cycle and inspect the squeegee blade for damage.'
       WHEN ROOT_CAUSE ILIKE '%misplacement%' THEN 'run a placement accuracy check on the affected heads, verify fiducial recognition and re-check boards built since the last good AOI result.'
       WHEN ROOT_CAUSE ILIKE '%nozzle%' THEN 'inspect and clean the pickup nozzles, replace worn nozzles from critical spares and verify vacuum levels before restarting.'
       WHEN ROOT_CAUSE ILIKE '%reel%' THEN 'stop the line, verify every feeder against the setup sheet and segregate boards built since the last verified changeover.'
       WHEN ROOT_CAUSE ILIKE '%profile%' THEN 'run a profiling board with the thermocouple kit, compare zone temperatures and conveyor speed with the recipe window and hold boards until the profile is back in range.'
       WHEN ROOT_CAUSE ILIKE '%bridging%' OR ROOT_CAUSE ILIKE '%voiding%' THEN 'inspect sample joints with AOI and X-ray, check paste volume on the affected pads and review the reflow profile before releasing the lot.'
       WHEN ROOT_CAUSE ILIKE '%fixture%' THEN 'clean and inspect the ICT fixture probes, replace worn probes from critical spares and re-test boards that failed on contact.'
       WHEN ROOT_CAUSE ILIKE '%escape%' THEN 'review the AOI program thresholds for the escaped defect, re-inspect the lot and add the defect image to the AOI library.'
       WHEN ROOT_CAUSE ILIKE '%firmware%' THEN 'verify the firmware image checksum and programming station settings, then re-flash and re-test the affected boards.'
       WHEN ROOT_CAUSE ILIKE '%RF%' THEN 'check the RF test fixture cables and the calibration of the test instruments, then re-test the affected boards.'
       WHEN ROOT_CAUSE ILIKE '%power%' THEN 'confirm site power and UPS status, follow the restart sequence for each stage and re-check boards that were in the reflow oven or on test during the dip.'
       ELSE 'inspect the affected station, record readings and escalate to the area engineer if readings are out of tolerance.'
     END
  || ' Step 3: if critical-to-quality deviation exceeds 5% or board temperature at test exceeds 40 C after restart, keep the lot on hold. '
  || 'Step 4: record the root cause, failed boards and downtime in the plant quality system.' AS CONTENT
FROM causes;

CREATE OR REPLACE CORTEX SEARCH SERVICE SEARCH.PROCESS_SOP_SEARCH
  ON CONTENT
  ATTRIBUTES CATEGORY, ROOT_CAUSE
  WAREHOUSE = __DEMO_WH__
  TARGET_LAG = '7 days'
AS (SELECT DOC_ID, TITLE, CATEGORY, ROOT_CAUSE, CONTENT FROM SEARCH.PROCESS_DOCS);

-- ---------- Critical-to-quality deviation anomaly detection (train first 75 days, detect last 15) ----------
CREATE OR REPLACE VIEW ML.CTQ_DEV_SERIES AS
SELECT ENTITY_ID, EVENT_DATE::TIMESTAMP_NTZ AS TS, CTQ_DEV_PCT::FLOAT AS CTQ_DEV
FROM RAW.LINE_DAILY;
CREATE OR REPLACE VIEW ML.CTQ_DEV_TRAIN AS
SELECT * FROM ML.CTQ_DEV_SERIES WHERE TS < (SELECT DATEADD(day, -15, MAX(TS)) FROM ML.CTQ_DEV_SERIES);
CREATE OR REPLACE VIEW ML.CTQ_DEV_DETECT AS
SELECT * FROM ML.CTQ_DEV_SERIES WHERE TS >= (SELECT DATEADD(day, -15, MAX(TS)) FROM ML.CTQ_DEV_SERIES);

CREATE OR REPLACE SNOWFLAKE.ML.ANOMALY_DETECTION ML.CTQ_DEV_ANOMALY_MODEL(
  INPUT_DATA => SYSTEM$REFERENCE('VIEW', 'ML.CTQ_DEV_TRAIN'),
  SERIES_COLNAME => 'ENTITY_ID', TIMESTAMP_COLNAME => 'TS', TARGET_COLNAME => 'CTQ_DEV',
  LABEL_COLNAME => '');

CREATE OR REPLACE TABLE ML.CTQ_DEV_ANOMALIES AS
SELECT SERIES::VARCHAR AS ENTITY_ID, TS::DATE AS EVENT_DATE, Y AS CTQ_DEV, FORECAST AS EXPECTED,
       LOWER_BOUND, UPPER_BOUND, IS_ANOMALY, PERCENTILE
FROM TABLE(ML.CTQ_DEV_ANOMALY_MODEL!DETECT_ANOMALIES(
  INPUT_DATA => SYSTEM$REFERENCE('VIEW', 'ML.CTQ_DEV_DETECT'),
  SERIES_COLNAME => 'ENTITY_ID', TIMESTAMP_COLNAME => 'TS', TARGET_COLNAME => 'CTQ_DEV'));

-- ---------- Semantic view ----------
CREATE OR REPLACE SEMANTIC VIEW APP.PROCESS_ANALYTICS
  TABLES (
    lines AS CURATED.PERFORMANCE_SUMMARY PRIMARY KEY (ENTITY_ID)
      COMMENT = 'One row per process line, 90-day totals',
    risk AS ML.HOLD_RISK_SCORES PRIMARY KEY (ENTITY_ID)
      COMMENT = 'Latest next-7-day quality hold probability per line',
    causes AS CURATED.HOLD_CAUSES PRIMARY KEY (ROOT_CAUSE)
      COMMENT = 'Quality holds by root cause, 90 days',
    daily AS CURATED.TREND_ANALYSIS PRIMARY KEY (METRIC_DATE)
      COMMENT = 'Network-wide totals per day'
  )
  RELATIONSHIPS (risk_line AS risk (ENTITY_ID) REFERENCES lines)
  FACTS (
    lines.boards_passed_f AS BOARDS_PASSED,
    lines.boards_started_f AS BOARDS_STARTED,
    lines.defects_f AS DEFECT_COUNT,
    lines.holds_f AS HOLD_COUNT,
    lines.downtime_hours_f AS DOWNTIME_HOURS,
    lines.operating_hours_f AS OPERATING_HOURS,
    lines.planned_hours_f AS PLANNED_HOURS,
    risk.hold_prob_f AS HOLD_PROB_7D,
    causes.cause_holds_f AS HOLD_COUNT,
    causes.cause_failed_f AS BOARDS_FAILED,
    causes.cause_hours_f AS DOWNTIME_HOURS,
    daily.day_boards_passed_f AS BOARDS_PASSED,
    daily.day_boards_started_f AS BOARDS_STARTED,
    daily.day_holds_f AS HOLD_COUNT
  )
  DIMENSIONS (
    lines.line_id AS ENTITY_ID WITH SYNONYMS = ('entities', 'line', 'PCBA line', 'SMT line', 'production line'),
    lines.line_name AS ENTITY_NAME,
    lines.site AS REGION WITH SYNONYMS = ('plant', 'site', 'province', 'region') COMMENT = 'Vietnamese province of the fictional electronics plant',
    lines.process_stage AS CATEGORY WITH SYNONYMS = ('stage', 'line type', 'process step') COMMENT = 'Solder Paste Printing, SMT Placement, Reflow Soldering, AOI and ICT, Functional Test',
    risk.risk_band AS RISK_BAND COMMENT = 'High >= 0.5, Medium >= 0.25, else Low',
    risk.scored_as_of AS SCORED_AS_OF,
    causes.root_cause AS ROOT_CAUSE,
    daily.metric_date AS METRIC_DATE
  )
  METRICS (
    lines.line_count AS COUNT(lines.line_id) WITH SYNONYMS = ('number of entities', 'entity count', 'number of lines'),
    lines.fpy_pct AS 100 * SUM(lines.boards_passed_f) / NULLIF(SUM(lines.boards_started_f), 0)
      WITH SYNONYMS = ('first-pass yield', 'yield') COMMENT = 'Boards passed first time / boards started',
    lines.total_boards_passed AS SUM(lines.boards_passed_f),
    lines.total_defects AS SUM(lines.defects_f) WITH SYNONYMS = ('defects', 'defect count'),
    lines.quality_holds AS SUM(lines.holds_f) WITH SYNONYMS = ('holds', 'quality events', 'lot holds'),
    lines.defects_per_1k_boards AS 1000 * SUM(lines.defects_f) / NULLIF(SUM(lines.boards_started_f), 0)
      WITH SYNONYMS = ('defect rate', 'defects per thousand boards') COMMENT = 'Recorded defects per 1,000 boards started',
    lines.total_boards_started AS SUM(lines.boards_started_f) WITH SYNONYMS = ('throughput', 'board output', 'boards built'),
    lines.line_availability_pct AS 100 * SUM(lines.operating_hours_f) / NULLIF(SUM(lines.planned_hours_f), 0),
    lines.total_downtime_hours AS SUM(lines.downtime_hours_f),
    risk.avg_hold_prob AS AVG(risk.hold_prob_f),
    causes.cause_holds AS SUM(causes.cause_holds_f),
    causes.cause_boards_failed AS SUM(causes.cause_failed_f),
    causes.cause_downtime_hours AS SUM(causes.cause_hours_f),
    daily.daily_fpy_pct AS 100 * SUM(daily.day_boards_passed_f) / NULLIF(SUM(daily.day_boards_started_f), 0),
    daily.daily_holds AS SUM(daily.day_holds_f)
  )
  COMMENT = 'Synthetic Vietnam PCBA line quality analytics (demo)';

-- ---------- Cortex Agent ----------
CREATE OR REPLACE AGENT APP.PROCESS_AGENT
  COMMENT = 'Quality assistant over a synthetic network of Vietnamese PCBA production lines'
  FROM SPECIFICATION
$$
models:
  orchestration: claude-sonnet-4-5
instructions:
  response: "Answer only from tool results. State that data is synthetic. Give line IDs and numbers with units."
  orchestration: "Use process_analyst for first-pass yield, quality holds, defects per 1k boards, board throughput, lines, sites, risk and root causes. Use sop_search for hold response procedures."
tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: process_analyst
      description: "First-pass yield, quality holds, defects per 1k boards, boards started, line availability, root causes and hold-risk scores"
  - tool_spec:
      type: cortex_search
      name: sop_search
      description: "Synthetic quality-hold response SOPs by process stage and cause"
tool_resources:
  process_analyst:
    semantic_view: __DEMO_DB__.APP.PROCESS_ANALYTICS
    execution_environment:
      type: warehouse
      warehouse: __DEMO_WH__
  sop_search:
    name: __DEMO_DB__.SEARCH.PROCESS_SOP_SEARCH
    max_results: 3
    id_column: DOC_ID
    title_column: TITLE
$$;

-- ---------- Live-telemetry alert ----------
CREATE TABLE IF NOT EXISTS APP.ALERT_LOG (
  ALERTED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(), LINE_ID VARCHAR,
  EVENT_TS TIMESTAMP_NTZ, CTQ_DEV_PCT FLOAT, BOARD_TEMP_C FLOAT, SOP_HINT VARCHAR);

CREATE OR REPLACE NOTIFICATION INTEGRATION VN_ELECTRONICS_QUALITY_EMAIL_INT
  TYPE = EMAIL ENABLED = TRUE ALLOWED_RECIPIENTS = ('__ALERT_EMAIL__');

CREATE OR REPLACE PROCEDURE APP.LOG_LIVE_ALARMS()
RETURNS NUMBER
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
  n NUMBER;
BEGIN
  INSERT INTO APP.ALERT_LOG (LINE_ID, EVENT_TS, CTQ_DEV_PCT, BOARD_TEMP_C, SOP_HINT)
    SELECT t.LINE_ID, t.EVENT_TS, t.CTQ_DEV_PCT, t.BOARD_TEMP_C,
           'Check ' || ln.CATEGORY || ' SOPs; current risk band ' || COALESCE(r.RISK_BAND, 'n/a')
    FROM RAW.LIVE_TELEMETRY t
    JOIN RAW.LINES ln ON ln.ID = t.LINE_ID
    LEFT JOIN ML.HOLD_RISK_SCORES r ON r.ENTITY_ID = t.LINE_ID
    WHERE t.STATUS = 'ALARM'
      AND NOT EXISTS (SELECT 1 FROM APP.ALERT_LOG l WHERE l.LINE_ID = t.LINE_ID AND l.EVENT_TS = t.EVENT_TS);
  n := SQLROWCOUNT;
  IF (n > 0) THEN
    CALL SYSTEM$SEND_EMAIL('VN_ELECTRONICS_QUALITY_EMAIL_INT', '__ALERT_EMAIL__',
      '[Demo] Vietnam PCBA line quality alarm',
      'New live-telemetry alarms logged in APP.ALERT_LOG: ' || :n || '. Data is synthetic.');
  END IF;
  RETURN n;
END;
$$;

CREATE OR REPLACE ALERT APP.LIVE_ALARM_ALERT
  WAREHOUSE = __DEMO_WH__
  SCHEDULE = '5 MINUTE'
  IF (EXISTS (
    SELECT 1 FROM RAW.LIVE_TELEMETRY t
    WHERE t.STATUS = 'ALARM'
      AND NOT EXISTS (SELECT 1 FROM APP.ALERT_LOG l WHERE l.LINE_ID = t.LINE_ID AND l.EVENT_TS = t.EVENT_TS)))
  THEN CALL APP.LOG_LIVE_ALARMS();

-- ---------- On-demand refresh DAG (suspended; run with EXECUTE TASK APP.TASK_REFRESH_CURATED) ----------
CREATE OR REPLACE PROCEDURE APP.REFRESH_CURATED()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
BEGIN
  ALTER DYNAMIC TABLE CURATED.PERFORMANCE_SUMMARY REFRESH;
  ALTER DYNAMIC TABLE CURATED.TREND_ANALYSIS REFRESH;
  ALTER DYNAMIC TABLE CURATED.HOLD_CAUSES REFRESH;
  ALTER DYNAMIC TABLE CURATED.KPI_SUMMARY REFRESH;
  RETURN 'refreshed';
END;
$$;

CREATE OR REPLACE TASK APP.TASK_REFRESH_CURATED
  WAREHOUSE = __DEMO_WH__
AS
  CALL APP.REFRESH_CURATED();

CREATE OR REPLACE TASK APP.TASK_RESCORE_RISK
  WAREHOUSE = __DEMO_WH__
  AFTER APP.TASK_REFRESH_CURATED
AS
  CREATE OR REPLACE TABLE ML.HOLD_RISK_SCORES COPY GRANTS AS
  WITH latest AS (
    SELECT * FROM ML.HOLD_FEATURES QUALIFY ROW_NUMBER() OVER (PARTITION BY ENTITY_ID ORDER BY EVENT_DATE DESC) = 1
  ), p AS (
    SELECT ENTITY_ID, EVENT_DATE,
           ML.HOLD_RISK_MODEL!PREDICT(INPUT_DATA => OBJECT_CONSTRUCT(
             'CATEGORY', CATEGORY, 'AGE_YEARS', AGE_YEARS, 'CTQ_DEV_PCT', CTQ_DEV_PCT,
             'BOARD_TEMP_C', BOARD_TEMP_C, 'CTQ_DEV_7D', CTQ_DEV_7D, 'HOLDS_30D', HOLDS_30D)) AS PRED
    FROM latest
  )
  SELECT ENTITY_ID, EVENT_DATE AS SCORED_AS_OF, ROUND(PRED:probability:HOLD::FLOAT, 4) AS HOLD_PROB_7D,
         CASE WHEN PRED:probability:HOLD::FLOAT >= 0.5 THEN 'High'
              WHEN PRED:probability:HOLD::FLOAT >= 0.25 THEN 'Medium' ELSE 'Low' END AS RISK_BAND,
         CURRENT_TIMESTAMP() AS SCORED_AT
  FROM p;
