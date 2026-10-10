# Vietnam Electronics PCBA Quality - Quality Holds and First-Pass Yield

Board-level quality operations for **24 PCBA (printed circuit board assembly) lines across 5 northern Vietnamese provinces** (Bac Ninh, Bac Giang, Hai Phong, Thai Nguyen, Vinh Phuc) using Snowflake, optionally with AWS: from a live test-station alarm to a 7-day quality-hold risk score, an alarm email and an AI action memo for the quality team.

## Architecture

A PCBA line quality pipeline built on **Snowflake** (Dynamic Tables, Snowflake ML, Cortex Search, Cortex Agent, Cortex AI_COMPLETE, SPCS) and, in the full build, **AWS** (IoT Core, S3, Bedrock Claude, QuickSight + Amazon Q). Line test-station telemetry lands in `RAW.LIVE_TELEMETRY`. Dynamic tables curate 90 days of line-day history: first-pass yield, recorded defects per 1,000 boards, quality holds and line availability. Snowflake ML scores 7-day quality-hold risk per line, forecasts network-wide first-pass yield and flags critical-to-quality (CTQ) deviation anomalies such as solder paste volume drift. A Cortex Agent answers questions with SOP citations, and an LLM drafts the quality action memo.

Interactive diagrams (hover for object names): [Snowflake only](docs/architecture-snowflake.html) | [AWS + Snowflake](docs/architecture-aws.html). The app shows both on its Architecture & Data tab, the current build first. Regenerate them with `python3 docs/build_architecture.py`.

```mermaid
flowchart LR
    subgraph AWS
      SIM[publish_telemetry.py<br/>test-station sim] --> IOT[AWS IoT Core<br/>topic vn/pcbaquality/telemetry]
      IOT -->|topic rule| S3[(Amazon S3<br/>iot/ landing)]
      BR[Amazon Bedrock<br/>Claude Sonnet 4.5]
      QS[Amazon QuickSight<br/>dashboard + Q topic]
    end
    subgraph Snowflake
      S3 -->|SQS event| PIPE[Snowpipe AUTO_INGEST] --> LIVE[RAW.LIVE_TELEMETRY]
      GEN[02_raw_tables.sql<br/>seeded generator] --> RAW[RAW.LINES / LINE_DAILY / CRITICAL_SPARES]
      RAW --> DT[CURATED dynamic tables]
      RAW --> ML[Snowflake ML<br/>CLASSIFICATION risk, FORECAST,<br/>ANOMALY_DETECTION]
      DT --> SV[Semantic view<br/>APP.PROCESS_ANALYTICS]
      RAW --> CS[Cortex Search<br/>quality-hold SOPs]
      SV --> AG[Cortex Agent<br/>APP.PROCESS_AGENT]
      CS --> AG
      LIVE --> AL[Alert APP.LIVE_ALARM_ALERT<br/>+ email]
      UDF[APP.BEDROCK_GENERATE<br/>external access UDF]
      TK[Task graph: refresh, then rescore]
      APP[Next.js app on SPCS]
    end
    BR <--> UDF
    DT --> APP
    ML --> APP
    LIVE --> APP
    AG --> APP
    UDF --> APP
    DT --> QS
    ML --> QS
    LIVE --> QS
```

The Snowflake-only build drops the AWS subgraph: `APP.SIMULATE_TELEMETRY` writes to `RAW.LIVE_TELEMETRY`, and the app calls Cortex `AI_COMPLETE` instead of the Bedrock UDF.

## Snowflake Capabilities

| Capability | Implementation |
|-----------|---------------|
| Dynamic Tables | `CURATED.KPI_SUMMARY`, `PERFORMANCE_SUMMARY`, `HOLD_CAUSES`, `TREND_ANALYSIS` from the RAW tables |
| Snowflake ML | CLASSIFICATION 7-day quality-hold risk (`ML.HOLD_RISK_SCORES`), 14-day first-pass yield FORECAST, CTQ deviation ANOMALY_DETECTION |
| Cortex Search | 18 synthetic quality-hold response SOPs (one per process stage and hold cause) in `SEARCH.PROCESS_SOP_SEARCH` |
| Semantic View | `APP.PROCESS_ANALYTICS` over lines, hold causes, daily yield and risk |
| Cortex Agent | `APP.PROCESS_AGENT`: Cortex Analyst over the semantic view plus Cortex Search for SOP citations |
| Cortex AI | `AI_COMPLETE('claude-sonnet-4-5')` for grounded answers, and for the action memo in the Snowflake-only build |
| Alerts + Tasks | `APP.LIVE_ALARM_ALERT` logs ALARM readings and sends email; task graph `TASK_REFRESH_CURATED`, then `TASK_RESCORE_RISK` |
| Snowpark Container Services | Next.js app `APP.VN_ELECTRONICS_QUALITY_APP` with 6 tabs: Executive Cockpit, Predictive, Line Health, Live IoT, Ask AI, Architecture & Data |
| Snowpipe | `RAW.LIVE_TELEMETRY_PIPE` AUTO_INGEST from S3 (AWS build only) |

## AWS Services

Used only in the AWS + Snowflake build.

| Service | Role in Demo |
|---------|-------------|
| AWS IoT Core | Receives simulated line test-station telemetry (CTQ deviation, board temperature at test). A topic rule writes each message to S3 |
| Amazon S3 | Landing bucket. An event notification goes to the Snowpipe SQS queue |
| Amazon Bedrock | Claude Sonnet 4.5 writes the action memo, called from Snowflake through an external-access UDF |
| Amazon QuickSight | DIRECT_QUERY executive dashboard over Snowflake (daily first-pass yield, holds by line, hold risk) |
| Amazon Q | Natural-language questions over the QuickSight topic `vn-electronics-quality-topic` |
| AWS IAM | Least-privilege roles for S3, IoT and Bedrock |

## Personas

These personas are fictional.

| Persona | Role | Key Questions |
|---------|------|---------------|
| **Nguyen Thi Lan** | VP Quality | "Which province has the lowest first-pass yield?" "Which hold causes fail the most boards first pass?" |
| **Tran Minh Duc** | SMT Process Quality Engineer | "Which lines are high hold risk this week, and which SOP applies?" "Where are defects per 1k boards highest?" |

## Data

All data is synthetic and seeded, so every rebuild reproduces it. Plants, lines, products and operators are fictional; the five provinces are real Vietnamese locations, and no figure describes a real company or plant.

| Table | Rows | Description |
|-------|------|-------------|
| RAW.LINES | 24 | PCBA lines across 5 provinces and 5 stages (Solder Paste Printing, SMT Placement, Reflow Soldering, AOI and ICT, Functional Test), smartphone mainboard or wearable module, components per board |
| RAW.LINE_DAILY | 2,160 | Daily line observations over 90 days: boards started and passed first time, recorded defects, holds, root cause, PM, CTQ deviation and board temperature at test |
| RAW.CRITICAL_SPARES | 24 | Required and on-hand critical fixture and tooling spares per line (stencils, nozzles, ICT probes, test fixtures) |
| SEARCH.PROCESS_DOCS | 18 | Synthetic quality-hold response SOPs indexed for Cortex Search |
| RAW.LIVE_TELEMETRY | Grows during the demo | Live readings from IoT Core (AWS build) or `APP.SIMULATE_TELEMETRY` (Snowflake-only build) |
| ML.HOLD_RISK_SCORES | 24 | 7-day quality-hold probability and risk band per line |

## Build Instructions

### Prerequisites
- Snowflake account with ACCOUNTADMIN access, and Cortex AI enabled (AI_COMPLETE, Search, Agent).
- An X-Small warehouse with auto-suspend at or below 120 s, and an existing SPCS compute pool.
- Python 3.11+, `snowflake-connector-python`, Node.js 22+, Docker and the `snow` CLI.
- App image: run `snow spcs image-registry login`, then build and push `vn-electronics-quality-app:v1` to the database's `APP.IMAGES` repository (see the header of `snowflake/07_deploy_app.sql`).
- AWS build only: `boto3`, AWS credentials for the target account (us-west-2) with Bedrock access, and QuickSight Enterprise.

### SPCS App
```
<DATABASE>.APP.VN_ELECTRONICS_QUALITY_APP
```

### Tests
```bash
python -m pytest aws snowflake quicksight
```

For a local run, put `SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER`, `SNOWFLAKE_DATABASE`, `SNOWFLAKE_WAREHOUSE`, `SNOWFLAKE_AUTHENTICATOR=PROGRAMMATIC_ACCESS_TOKEN`, `SNOWFLAKE_TOKEN` and `DEMO_PLATFORM` in the environment, then run `npm --prefix app run build && npm --prefix app start`.

## Build Modes

Both modes share the same core. They differ in three places, and the app's `DEMO_PLATFORM` setting (in its SPCS spec) switches the memo provider and the Live IoT tab.

| Layer | Snowflake Only | Full AWS + Snowflake |
|---|---|---|
| Live telemetry | `CALL APP.SIMULATE_TELEMETRY(n)` inserts simulated readings into `RAW.LIVE_TELEMETRY`. This simulates a sensor feed; it is not Snowpipe Streaming | `aws/publish_telemetry.py` to AWS IoT Core, then S3, SQS and Snowpipe AUTO_INGEST |
| Action memo | Cortex `AI_COMPLETE('claude-sonnet-4-5')` | Amazon Bedrock Claude Sonnet 4.5 through `APP.BEDROCK_GENERATE` |
| BI and natural-language questions | The SPCS app is the dashboard; questions go to the Cortex Agent | Also a QuickSight dashboard and an Amazon Q topic |
| App setting | `DEMO_PLATFORM: snowflake` | `DEMO_PLATFORM: aws` |

### Snowflake Only

```bash
# 1. Core data and dynamic tables (guarded: new isolated database only)
python snowflake/run_core.py --database VIETNAM_ELECTRONICS_QUALITY_SNOWFLAKE --warehouse <XS_WAREHOUSE> --connection <CONNECTION> --apply
# 2. Native telemetry, ML, search, semantic view, agent, alert and task graph
python snowflake/run_intelligence.py --database VIETNAM_ELECTRONICS_QUALITY_SNOWFLAKE --platform snowflake --warehouse <XS_WAREHOUSE> --connection <CONNECTION> --alert-email you@example.com
# 3. App on SPCS with DEMO_PLATFORM=snowflake (push the image first)
python snowflake/run_intelligence.py --database VIETNAM_ELECTRONICS_QUALITY_SNOWFLAKE --platform snowflake --warehouse <XS_WAREHOUSE> --connection <CONNECTION> --alert-email you@example.com --files 07_deploy_app.sql --compute-pool <COMPUTE_POOL>
```

During the demo:
- Run `CALL APP.SIMULATE_TELEMETRY(20)` to add live readings. For a continuous feed, run `ALTER TASK APP.TASK_SIMULATE_TELEMETRY RESUME`, and `SUSPEND` it afterwards.
- Run `EXECUTE ALERT APP.LIVE_ALARM_ALERT` to raise the alarm email.
- Run `EXECUTE TASK APP.TASK_REFRESH_CURATED` to refresh the curated tables and rescore risk.

Afterwards, drop the database or run `ALTER SERVICE APP.VN_ELECTRONICS_QUALITY_APP SUSPEND`.

### Full AWS + Snowflake

```bash
# 1. Core data and dynamic tables (guarded: new isolated database only)
python snowflake/run_core.py --database VIETNAM_ELECTRONICS_QUALITY_AWS --warehouse <XS_WAREHOUSE> --connection <CONNECTION> --apply
# 2. AWS ingestion and Bedrock (dry run first, then --apply)
python aws/setup_aws.py --database VIETNAM_ELECTRONICS_QUALITY_AWS --account <AWS_ACCOUNT_ID> --connection <CONNECTION> --apply
# 3. ML, search, semantic view, agent, alert and task graph
python snowflake/run_intelligence.py --database VIETNAM_ELECTRONICS_QUALITY_AWS --platform aws --warehouse <XS_WAREHOUSE> --connection <CONNECTION> --alert-email you@example.com
# 4. App on SPCS with DEMO_PLATFORM=aws (push the image first)
python snowflake/run_intelligence.py --database VIETNAM_ELECTRONICS_QUALITY_AWS --platform aws --warehouse <XS_WAREHOUSE> --connection <CONNECTION> --alert-email you@example.com --files 07_deploy_app.sql --compute-pool <COMPUTE_POOL>
# 5. QuickSight dashboard and Q topic (needs an existing Snowflake data source)
python quicksight/build_dashboards.py --database VIETNAM_ELECTRONICS_QUALITY_AWS --account <AWS_ACCOUNT_ID> --principal-arn <QUICKSIGHT_USER_ARN> --data-source-arn <DATA_SOURCE_ARN> --prefix vn-electronics-quality --apply --update --with-topic
```

QuickSight objects must be shared with the QuickSight user who signs in (`--principal-arn`); otherwise the console shows nothing.

During the demo:
- Run `python aws/publish_telemetry.py --count 20` to send live readings.
- Run `EXECUTE ALERT APP.LIVE_ALARM_ALERT` to raise the alarm email.
- Run `EXECUTE TASK APP.TASK_REFRESH_CURATED` to refresh the curated tables and rescore risk.

Afterwards, `python aws/teardown_aws.py --database VIETNAM_ELECTRONICS_QUALITY_AWS --account <AWS_ACCOUNT_ID> --connection <CONNECTION> --apply` removes the AWS resources and the account-level Bedrock external-access and S3 storage integrations. It leaves the email integration `VN_ELECTRONICS_QUALITY_EMAIL_INT`, which the Snowflake-only build also uses.

## Business Impact

Snowflake customer outcomes in manufacturing quality:
- **Valmet** (Snowflake customer) runs its Anomaly Detector application on Snowflake. It "has been proven to catch 15-20% of potential web breaks", and "the improved efficiency generated by Anomaly Detection generates an annual savings of 300,000 euros" -- [Snowflake blog, Optimizing the Manufacturing Process at Valmet](https://www.snowflake.com/blog/optimizing-the-manufacturing-process-at-valmet-powered-by-the-snowflake-data-cloud/)
- **Valmet Online Quality Predictor** predicts real-time paper strength and alerts operators; "the result of these operator actions is a 1-7% bottom line savings in paper fiber depending on produced grade" -- [same Snowflake blog](https://www.snowflake.com/blog/optimizing-the-manufacturing-process-at-valmet-powered-by-the-snowflake-data-cloud/)
- **Purple** (Snowflake customer): "We increased the number of mattresses we build each day and focus on improving that yield, thanks to the clarity of data. Snowflake helps us quickly pinpoint any irregularities." -- Scott Clark, Head of Analytics, [Snowflake Power Smart Manufacturing & Industry 4.0](https://www.snowflake.com/en/solutions/industries/manufacturing/power-smart-manufacturing/)

These are outcomes in other manufacturing processes (paper, mattresses), not PCBA results.

## Key Demo Numbers

These figures are synthetic and come from the seeded demo data. Forecast and anomaly figures can shift slightly with the build day.

- **24 lines**, 2,160 line-days over 90 days, across 5 provinces and 5 process stages
- **First-pass yield 95.7%**; per-line yield ranges from 93.1% to 97.6%, and Vinh Phuc is the lowest province at 95.2%
- **163 quality holds** across 14 root causes; ICT fixture contact fault fails the most boards first pass (15,843 boards on hold days)
- **21.01 defects per 1k boards** over 11,773,964 boards started; AOI and ICT has the highest rate (33.3); line availability 99.1%
- **Hold-risk model** out-of-time holdout: precision 0.51, recall 0.48 at a 0.5 threshold, against a 0.29 base rate. Seven lines are high risk; the top line is SMT-0021, at 98.0%
- **14-day first-pass yield forecast** with prediction intervals; **22 of 384** line-days flagged as CTQ deviation anomalies
- **18 SOPs** indexed for Cortex Search and cited by ID in agent answers

## License

Apache 2.0 — See [LICENSE](LICENSE) for details.

This is a personal demo project and is not an official Snowflake offering. It comes with no support or warranty. Industry metrics cited are from publicly available third-party research; they represent reported outcomes and are not guarantees of results.
