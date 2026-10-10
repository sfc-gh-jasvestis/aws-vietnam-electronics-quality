import { NextResponse } from 'next/server';
import { demoPlatform } from '@/lib/platform';
import { executeQuery } from '@/lib/snowflake';

export const dynamic = 'force-dynamic';
export const revalidate = 0;

export async function GET() {
  try {
    const [kpis, trend, causes, lines, freshness, risk, holdout, forecast, live, liveSummary, anomalies, alerts] = await Promise.all([
      executeQuery<{ TITLE: string; DISPLAY: string; STATUS: string }>(
        'SELECT TITLE, DISPLAY, STATUS FROM CURATED.KPI_SUMMARY ORDER BY SORT_ORDER'),
      executeQuery<{ PERIOD: string; VALUE: number | null }>(`
        SELECT TO_CHAR(METRIC_DATE, 'YYYY-MM-DD') AS PERIOD,
               FIRST_PASS_YIELD_PCT AS VALUE
        FROM CURATED.TREND_ANALYSIS ORDER BY METRIC_DATE`),
      executeQuery<{ CATEGORY: string; COUNT: number }>(`
        SELECT ROOT_CAUSE AS CATEGORY, BOARDS_FAILED AS COUNT
        FROM CURATED.HOLD_CAUSES ORDER BY BOARDS_FAILED DESC`),
      executeQuery<Record<string, string | number | null>>(`
        SELECT ENTITY_ID, ENTITY_NAME, REGION, CATEGORY, EVENT_COUNT, HOLD_COUNT,
               FIRST_PASS_YIELD_PCT, DEFECTS_PER_1K_BOARDS, LINE_AVAILABILITY_PCT, PM_COMPLIANCE_PCT
        FROM CURATED.PERFORMANCE_SUMMARY ORDER BY ENTITY_ID LIMIT 200`),
      executeQuery<{ RAW_WATERMARK: string | null; CURATED_WATERMARK: string | null }>(`
        SELECT (SELECT TO_CHAR(MAX(EVENT_DATE), 'YYYY-MM-DD') FROM RAW.LINE_DAILY) AS RAW_WATERMARK,
               (SELECT TO_CHAR(MAX(METRIC_DATE), 'YYYY-MM-DD') FROM CURATED.TREND_ANALYSIS) AS CURATED_WATERMARK`),
      executeQuery<Record<string, string | number | null>>(`
        SELECT ENTITY_ID, TO_CHAR(SCORED_AS_OF, 'YYYY-MM-DD') AS SCORED_AS_OF, HOLD_PROB_7D, RISK_BAND
        FROM ML.HOLD_RISK_SCORES ORDER BY HOLD_PROB_7D DESC`),
      executeQuery<Record<string, string | number | null>>(
        'SELECT N, BASE_RATE, PRECISION_AT_50, RECALL_AT_50 FROM ML.HOLD_RISK_HOLDOUT_METRICS'),
      executeQuery<Record<string, string | number | null>>(`
        SELECT TO_CHAR(FORECAST_DATE, 'YYYY-MM-DD') AS PERIOD, FIRST_PASS_YIELD_PCT, LOWER_BOUND, UPPER_BOUND
        FROM ML.YIELD_FORECAST ORDER BY FORECAST_DATE`),
      executeQuery<Record<string, string | number | null>>(`
        SELECT LINE_ID, TO_CHAR(EVENT_TS, 'YYYY-MM-DD HH24:MI:SS') AS EVENT_TS, CTQ_DEV_PCT, BOARD_TEMP_C, STATUS,
               TO_CHAR(LOADED_AT, 'YYYY-MM-DD HH24:MI:SS TZH:TZM') AS LOADED_AT
        FROM RAW.LIVE_TELEMETRY ORDER BY EVENT_TS DESC LIMIT 25`),
      executeQuery<Record<string, string | number | null>>(`
        SELECT COUNT(*) AS N, COUNT_IF(STATUS = 'ALARM') AS ALARMS,
               TO_CHAR(MAX(LOADED_AT), 'YYYY-MM-DD HH24:MI:SS TZH:TZM') AS LAST_LOADED,
               ROUND(MEDIAN(DATEDIFF('second', IOT_RECEIVED_TS, CONVERT_TIMEZONE('UTC', LOADED_AT)::TIMESTAMP_NTZ)), 0) AS MEDIAN_LAG_S
        FROM RAW.LIVE_TELEMETRY`),
      executeQuery<Record<string, string | number | null>>(`
        SELECT ENTITY_ID, TO_CHAR(EVENT_DATE, 'YYYY-MM-DD') AS EVENT_DATE, ROUND(CTQ_DEV, 2) AS CTQ_DEV,
               ROUND(EXPECTED, 2) AS EXPECTED, ROUND(UPPER_BOUND, 2) AS UPPER_BOUND
        FROM ML.CTQ_DEV_ANOMALIES WHERE IS_ANOMALY ORDER BY EVENT_DATE DESC, ENTITY_ID LIMIT 50`),
      executeQuery<Record<string, string | number | null>>(`
        SELECT LINE_ID, TO_CHAR(EVENT_TS, 'YYYY-MM-DD HH24:MI:SS') AS EVENT_TS, CTQ_DEV_PCT, BOARD_TEMP_C, SOP_HINT
        FROM APP.ALERT_LOG ORDER BY ALERTED_AT DESC, EVENT_TS DESC LIMIT 25`),
    ]);
    const numberOrNull = (value: unknown): number | null => {
      if (value === null || value === undefined) return null;
      const numeric = Number(value);
      if (!Number.isFinite(numeric)) throw new Error('Non-numeric measure in curated contract');
      return numeric;
    };
    const watermark = freshness[0]?.CURATED_WATERMARK ?? null;
    const ageDays = watermark ? (Date.now() - Date.parse(`${watermark}T00:00:00Z`)) / 86400000 : null;
    return NextResponse.json({
      platform: demoPlatform(),
      kpiCards: kpis.map((row) => ({ title: row.TITLE, value: row.DISPLAY, status: row.STATUS })),
      timeseries: trend.map((row) => ({ period: row.PERIOD, value: numberOrNull(row.VALUE) })),
      categories: causes.map((row) => ({ category: row.CATEGORY, count: numberOrNull(row.COUNT) })),
      entities: lines.map((row) => ({
        id: row.ENTITY_ID, name: row.ENTITY_NAME, region: row.REGION, category: row.CATEGORY,
        yieldPct: numberOrNull(row.FIRST_PASS_YIELD_PCT), defects: numberOrNull(row.DEFECTS_PER_1K_BOARDS),
        availability: numberOrNull(row.LINE_AVAILABILITY_PCT), pm: numberOrNull(row.PM_COMPLIANCE_PCT),
        events: numberOrNull(row.EVENT_COUNT), holds: numberOrNull(row.HOLD_COUNT),
      })),
      pmYield: lines.map((row) => ({
        name: row.ENTITY_NAME, compliance: numberOrNull(row.PM_COMPLIANCE_PCT), yieldPct: numberOrNull(row.FIRST_PASS_YIELD_PCT),
      })).filter((row) => row.compliance !== null && row.yieldPct !== null),
      sourceWatermark: watermark,
      rawWatermark: freshness[0]?.RAW_WATERMARK ?? null,
      stale: ageDays === null || ageDays > 2,
      pipelineBehind: freshness[0]?.RAW_WATERMARK !== watermark,
      requestedAt: new Date().toISOString(),
      synthetic: true,
      risk: risk.map((row) => ({
        id: row.ENTITY_ID, scoredAsOf: row.SCORED_AS_OF,
        probability: numberOrNull(row.HOLD_PROB_7D), band: row.RISK_BAND,
      })),
      holdout: holdout[0] ? {
        n: numberOrNull(holdout[0].N), baseRate: numberOrNull(holdout[0].BASE_RATE),
        precision: numberOrNull(holdout[0].PRECISION_AT_50), recall: numberOrNull(holdout[0].RECALL_AT_50),
      } : null,
      forecast: forecast.map((row) => ({
        period: row.PERIOD, value: numberOrNull(row.FIRST_PASS_YIELD_PCT),
        lower: numberOrNull(row.LOWER_BOUND), upper: numberOrNull(row.UPPER_BOUND),
      })),
      modelStatus: holdout[0] ? 'holdout_evaluated' : 'missing',
      live: live.map((row) => ({
        id: row.LINE_ID, eventTs: row.EVENT_TS, deviation: numberOrNull(row.CTQ_DEV_PCT),
        temperature: numberOrNull(row.BOARD_TEMP_C), status: row.STATUS, loadedAt: row.LOADED_AT,
      })),
      liveSummary: {
        n: numberOrNull(liveSummary[0]?.N), alarms: numberOrNull(liveSummary[0]?.ALARMS),
        lastLoaded: liveSummary[0]?.LAST_LOADED ?? null, medianLagSeconds: numberOrNull(liveSummary[0]?.MEDIAN_LAG_S),
      },
      anomalies: anomalies.map((row) => ({
        id: row.ENTITY_ID, date: row.EVENT_DATE, deviation: numberOrNull(row.CTQ_DEV),
        expected: numberOrNull(row.EXPECTED), upper: numberOrNull(row.UPPER_BOUND),
      })),
      alerts: alerts.map((row) => ({
        id: row.LINE_ID, eventTs: row.EVENT_TS, deviation: numberOrNull(row.CTQ_DEV_PCT),
        temperature: numberOrNull(row.BOARD_TEMP_C), hint: row.SOP_HINT,
      })),
    }, { headers: { 'Cache-Control': 'no-store' } });
  } catch {
    return NextResponse.json({ error: 'Process data is unavailable. Verify the core deployment and application role.' },
      { status: 503, headers: { 'Cache-Control': 'no-store' } });
  }
}
