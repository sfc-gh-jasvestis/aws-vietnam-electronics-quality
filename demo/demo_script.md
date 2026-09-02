# Quality Analytics & Defect Prediction

**Vietnam - Electronics Manufacturing**
Use case: Quality Analytics

> Quality Analytics & Defect Prediction for Vietnam - ML.FORECAST and Dynamic Tables power real-time quality analytics intelligence for electronics manufacturing in Ho Chi Minh City & Bac Ninh.

## Why Snowflake

Snowflake delivers quality analytics intelligence for Vietnamese electronics manufacturing - Dynamic Tables maintain real-time dashboards, ML.FORECAST projects key metrics, and Cortex AI generates recommendations

- **ML.FORECAST for quality analytics** - Only demo for Vietnamese electronics manufacturing
- **ML.ANOMALY_DETECTION early warning** - Detects deviations before impact
- **AI recommendations** - Cortex AI actionable guidance
- **Vietnamese context** - Local names, VND economics

## What is deployed

| | |
|---|---|
| Database | `VIETNAM_ELECTRONICS_QUALITY` |
| Service | `VIETNAM_ELECTRONICS_QUALITY_APP` |
| Compute pool | `SEA_DEMOS_VIETNAM_POOL` |
| Dimension table | `RAW.DOCUMENTS` (20 rows) |
| Fact table | `RAW.METRICS` (250,000 rows, 90 days) |
| Curated layer | `CURATED.PERFORMANCE_SUMMARY`, `CURATED.TREND_ANALYSIS`, `CURATED.KPI_SUMMARY` |
| Currency | VND (₫) |

Regions in play: Ho Chi Minh City, Hanoi, Binh Duong, Dong Nai, Can Tho
Segments: Solder Defect, Component Placement, Cosmetic, Functional Test

Dynamic tables are created suspended and refreshed on demand:

```bash
./refresh_demo_data.sh VIETNAM_ELECTRONICS_QUALITY
```

## KPI cards

Every card below is served live from `CURATED.KPI_SUMMARY`. The app keeps the
original literal as a fallback, so it still renders if Snowflake is unreachable.

| Card | Value | Backed by |
|---|---|---|
| First Pass Yield | `98.4%` | average per event |
| Customer Returns | `0.08%` | average per event |
| Quality Escapes | `2` | average per event |
| Inspections (MTD) | `4.2M` | total across Documents |
| DPMO | `124` | total across Documents |
| Rework Rate | `1.2%` | average per event |
| AOI Detection | `99.4%` | average per event |


## Demo flow

1. Overview
2. Analytics
3. AI Intelligence
4. Ask AI
5. Architecture

## Talking points

- **100K operations** - tracked in Ho Chi Minh City & Bac Ninh
- **500K metrics** - time-series data points
- **5K assets** - monitored
- **100 docs** - searchable

## Business impact

- Vietnam electronics manufacturing sector growing rapidly (GSO Vietnam)
- AI improves outcomes 15-30% (McKinsey)
- Vietnam FDI strong in this sector (MPI)
- Real-time analytics reduces response 60-80% (Gartner)

---
Generated from `generator/demo_specs/aws-vietnam-electronics-quality.json`. Do not hand-edit: run
`python3 generator/gen_repo_docs.py aws-vietnam-electronics-quality` instead.
