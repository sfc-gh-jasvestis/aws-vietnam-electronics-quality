-- Synthetic line-day observations for PCBA (printed circuit board assembly)
-- lines, from solder paste printing to functional test. Nothing is seeded as a
-- prediction. Randomness is HASH-seeded, so every rebuild is reproducible:
-- per-line age and quality-hold propensity, wear between maintenance windows,
-- missed PM, stage-weighted hold causes, and two site-wide utility power dips.
-- Plants, lines and products are fictional.
USE DATABASE IDENTIFIER($DEMO_DB);
USE SCHEMA RAW;
USE WAREHOUSE IDENTIFIER($DEMO_WH);

CREATE TABLE RAW.LINES AS
WITH lines AS (
  SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS LINE_INDEX
  FROM TABLE(GENERATOR(ROWCOUNT => 24))
), draws AS (
  SELECT LINE_INDEX,
         MOD(ABS(HASH(LINE_INDEX, 'vneq-age')), 1000000) / 1e6 AS U_AGE,
         MOD(ABS(HASH(LINE_INDEX, 'vneq-rate')), 1000000) / 1e6 AS U_RATE,
         MOD(ABS(HASH(LINE_INDEX, 'vneq-pm')), 1000000) / 1e6 AS U_PM,
         MOD(ABS(HASH(LINE_INDEX, 'vneq-discipline')), 1000000) / 1e6 AS U_DISCIPLINE,
         MOD(ABS(HASH(LINE_INDEX, 'vneq-parts')), 1000000) / 1e6 AS U_PARTS
  FROM lines
)
SELECT 'SMT-' || LPAD(LINE_INDEX::VARCHAR, 4, '0') AS ID,
       'Synthetic PCBA line ' || LPAD(LINE_INDEX::VARCHAR, 4, '0') AS NAME,
       -- Deterministic spread (8 and 5 are coprime): every site and stage is present.
       CASE MOD(LINE_INDEX, 8) WHEN 0 THEN 'Bac Ninh' WHEN 1 THEN 'Bac Ninh' WHEN 2 THEN 'Bac Ninh'
            WHEN 3 THEN 'Bac Giang' WHEN 4 THEN 'Bac Giang' WHEN 5 THEN 'Thai Nguyen' WHEN 6 THEN 'Hai Phong'
            ELSE 'Vinh Phuc' END AS REGION,
       CASE MOD(LINE_INDEX, 5) WHEN 0 THEN 'Solder Paste Printing' WHEN 1 THEN 'SMT Placement'
            WHEN 2 THEN 'Reflow Soldering' WHEN 3 THEN 'AOI and ICT' ELSE 'Functional Test' END AS CATEGORY,
       IFF(MOD(LINE_INDEX, 3) = 0, 'Wearable module', 'Smartphone mainboard') AS PRODUCT_FAMILY,
       LINE_INDEX,
       ROUND(1 + U_AGE * 9, 1) AS AGE_YEARS,
       -- Base daily hold probability 0.6%-3%; ~14% of lines are chronic (x3).
       (0.006 + U_RATE * 0.024) * IFF(U_RATE > 0.86, 3, 1) AS BASE_HOLD_RATE,
       7 * (1 + FLOOR(U_PM * 3)) AS PM_INTERVAL_DAYS,
       0.55 + U_DISCIPLINE * 0.45 AS PM_COMPLETION_PROB,
       -- Smartphone mainboards carry more placed components than wearable modules.
       ROUND(IFF(MOD(LINE_INDEX, 3) = 0, 240 + U_PARTS * 160, 900 + U_PARTS * 450)) AS COMPONENTS_PER_BOARD,
       'Active' AS STATUS
FROM draws;

CREATE TABLE RAW.LINE_DAILY AS
WITH days AS (
  SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS DAY_INDEX
  FROM TABLE(GENERATOR(ROWCOUNT => 90))
), power_dips AS (
  -- Two site-wide utility power dips in the window.
  SELECT * FROM VALUES (27, 'Bac Ninh', 3.0), (63, 'Hai Phong', 1.5) AS o(DAY_INDEX, REGION, HOURS)
), base AS (
  SELECT l.ID AS ENTITY_ID, l.LINE_INDEX, l.CATEGORY, l.REGION, l.AGE_YEARS,
         l.BASE_HOLD_RATE, l.PM_INTERVAL_DAYS, l.PM_COMPLETION_PROB,
         d.DAY_INDEX,
         DATEADD('day', d.DAY_INDEX - 89, CURRENT_DATE()) AS EVENT_DATE,
         24.0 AS PLANNED_HOURS,
         MOD(d.DAY_INDEX + l.LINE_INDEX * 5, l.PM_INTERVAL_DAYS) AS DAYS_SINCE_PM,
         MOD(ABS(HASH(l.ID, d.DAY_INDEX, 'vneq-hold')), 1000000) / 1e6 AS U_HOLD,
         MOD(ABS(HASH(l.ID, d.DAY_INDEX, 'vneq-down')), 1000000) / 1e6 + 1e-6 AS U_DOWN,
         MOD(ABS(HASH(l.ID, d.DAY_INDEX, 'vneq-cause')), 1000000) / 1e6 AS U_CAUSE,
         MOD(ABS(HASH(l.ID, d.DAY_INDEX, 'vneq-pmdone')), 1000000) / 1e6 AS U_PMDONE,
         MOD(ABS(HASH(l.ID, d.DAY_INDEX, 'vneq-rate')), 1000000) / 1e6 AS U_RATE,
         MOD(ABS(HASH(l.ID, d.DAY_INDEX, 'vneq-noise')), 1000000) / 1e6 AS U_NOISE,
         MOD(ABS(HASH(l.ID, d.DAY_INDEX, 'vneq-hit')), 1000000) / 1e6 AS U_HIT,
         p.HOURS AS DIP_HOURS
  FROM RAW.LINES l CROSS JOIN days d
  LEFT JOIN power_dips p ON p.DAY_INDEX = d.DAY_INDEX AND p.REGION = l.REGION
), pm AS (
  SELECT *,
         IFF(DAYS_SINCE_PM = 0, 1, 0) AS PM_DUE,
         IFF(DAYS_SINCE_PM = 0 AND U_PMDONE < PM_COMPLETION_PROB, 1, 0) AS PM_COMPLETED,
         -- Wear (stencils, nozzles, thermocouples, fixture probes) rises between PM; weak discipline carries it over.
         DAYS_SINCE_PM / PM_INTERVAL_DAYS + (1 - PM_COMPLETION_PROB) AS WEAR
  FROM base
), holds AS (
  SELECT *,
         CASE WHEN DIP_HOURS IS NOT NULL THEN 1
              WHEN U_HOLD < LEAST(0.5, BASE_HOLD_RATE * (0.4 + 1.6 * WEAR) * (1 + AGE_YEARS / 12)) / 4 THEN 2
              WHEN U_HOLD < LEAST(0.5, BASE_HOLD_RATE * (0.4 + 1.6 * WEAR) * (1 + AGE_YEARS / 12)) THEN 1
              ELSE 0 END AS HOLD_COUNT
  FROM pm
), timed AS (
  SELECT *,
         -- Line-down hours: exponential, mean depends on the stage.
         CASE WHEN HOLD_COUNT = 0 THEN 0.0
              WHEN DIP_HOURS IS NOT NULL THEN DIP_HOURS
              ELSE LEAST(18.0, ROUND(HOLD_COUNT * (0.5 - LN(U_DOWN) *
                   CASE CATEGORY WHEN 'Solder Paste Printing' THEN 2.0 WHEN 'SMT Placement' THEN 2.5
                                 WHEN 'Reflow Soldering' THEN 3.5 WHEN 'AOI and ICT' THEN 1.5 ELSE 3.0 END), 1))
         END AS DOWNTIME_HOURS
  FROM holds
), output AS (
  SELECT *,
         PLANNED_HOURS - DOWNTIME_HOURS AS OPERATING_HOURS,
         -- 160-300 boards per hour while running.
         ROUND((PLANNED_HOURS - DOWNTIME_HOURS) * (160 + U_RATE * 140)) AS BOARDS_STARTED,
         -- First-pass yield: base by stage, minus wear, age and the hold hit.
         LEAST(0.998, GREATEST(0.60,
           CASE CATEGORY WHEN 'Solder Paste Printing' THEN 0.988 WHEN 'SMT Placement' THEN 0.991
                         WHEN 'Reflow Soldering' THEN 0.978 WHEN 'AOI and ICT' THEN 0.972 ELSE 0.966 END
           - 0.018 * WEAR - 0.005 * AGE_YEARS / 10 - 0.007 * U_NOISE
           - HOLD_COUNT * (0.025 + 0.08 * U_HIT))) AS FIRST_PASS_YIELD,
         -- Recorded defects per board by stage; wear and holds add defects.
         CASE CATEGORY WHEN 'Solder Paste Printing' THEN 0.014 WHEN 'SMT Placement' THEN 0.008
                       WHEN 'Reflow Soldering' THEN 0.019 WHEN 'AOI and ICT' THEN 0.024 ELSE 0.011 END
           * (1 + 0.35 * WEAR + 0.9 * HOLD_COUNT + 0.12 * U_NOISE) AS DEFECTS_PER_BOARD
  FROM timed
)
SELECT ENTITY_ID || '-' || TO_CHAR(EVENT_DATE, 'YYYYMMDD') AS EVENT_ID,
       ENTITY_ID, EVENT_DATE, PLANNED_HOURS, DOWNTIME_HOURS, OPERATING_HOURS,
       HOLD_COUNT,
       CASE WHEN HOLD_COUNT = 0 THEN 'None'
            WHEN DIP_HOURS IS NOT NULL THEN 'Utility power dip'
            WHEN CATEGORY = 'Solder Paste Printing' THEN IFF(U_CAUSE < 0.5, 'Solder paste volume deviation', IFF(U_CAUSE < 0.8, 'Stencil aperture clogging', 'Paste print offset'))
            WHEN CATEGORY = 'SMT Placement' THEN IFF(U_CAUSE < 0.45, 'Component misplacement', IFF(U_CAUSE < 0.8, 'Nozzle pickup error', 'Wrong reel loaded'))
            WHEN CATEGORY = 'Reflow Soldering' THEN IFF(U_CAUSE < 0.5, 'Reflow profile drift', IFF(U_CAUSE < 0.8, 'Solder bridging', 'Solder voiding above limit'))
            WHEN CATEGORY = 'AOI and ICT' THEN IFF(U_CAUSE < 0.6, 'ICT fixture contact fault', 'AOI escape found downstream')
            ELSE IFF(U_CAUSE < 0.6, 'Firmware flash failure', 'RF calibration out of spec') END AS ROOT_CAUSE,
       PM_DUE, PM_COMPLETED,
       BOARDS_STARTED,
       ROUND(BOARDS_STARTED * FIRST_PASS_YIELD) AS BOARDS_PASSED,
       ROUND(BOARDS_STARTED * DEFECTS_PER_BOARD + DOWNTIME_HOURS * 3) AS DEFECT_COUNT,
       ROUND(0.6 + 1.8 * WEAR + 2.6 * HOLD_COUNT + U_NOISE * 0.8, 2) AS CTQ_DEV_PCT,
       ROUND(31 + 3.0 * WEAR + 4.5 * HOLD_COUNT + U_NOISE * 2, 1) AS BOARD_TEMP_C,
       CURRENT_TIMESTAMP() AS LOADED_AT
FROM output;

-- Critical fixture and tooling spares coverage per line (snapshot).
CREATE TABLE RAW.CRITICAL_SPARES AS
SELECT ID AS ENTITY_ID,
       CASE CATEGORY WHEN 'Solder Paste Printing' THEN 'Stencil and squeegee set' WHEN 'SMT Placement' THEN 'Placement nozzle set'
                     WHEN 'Reflow Soldering' THEN 'Reflow profiling thermocouple kit' WHEN 'AOI and ICT' THEN 'ICT fixture probe set'
                     ELSE 'Functional test fixture' END AS PART_TYPE,
       1 + MOD(ABS(HASH(ID, 'vneq-req')), 4) AS REQUIRED_QTY,
       MOD(ABS(HASH(ID, 'vneq-hand')), 5) AS ON_HAND_QTY,
       IFF(MOD(ABS(HASH(ID, 'vneq-hand')), 5) < 1 + MOD(ABS(HASH(ID, 'vneq-req')), 4),
           MOD(ABS(HASH(ID, 'vneq-order')), 3), 0) AS ON_ORDER_QTY,
       CURRENT_DATE() AS SNAPSHOT_DATE
FROM RAW.LINES;
