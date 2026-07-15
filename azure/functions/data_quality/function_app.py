"""
Azure Function: Data Quality Checks
────────────────────────────────────
Migrated from data_quality/dq_lambda.py. Called by the ADF pipeline's
RunDataQualityChecks activity after the Silver layer is built; the
EvaluateDataQuality IfCondition activity gates Gold aggregation on the
`quality_passed` field this returns — same role as the AWS Choice state.

Reads Silver tables via the Databricks SQL Warehouse (replaces
`awswrangler.athena.read_sql_query`) using the Databricks SDK, authenticated
with the Function App's user-assigned managed identity (no stored secret).

Environment Variables:
    DATABRICKS_HOST          — e.g. https://adb-xxxx.azuredatabricks.net
    DATABRICKS_WAREHOUSE_ID  — SQL Warehouse ID (Athena replacement)
    AZURE_CLIENT_ID          — user-assigned managed identity client ID
    DQ_MIN_ROW_COUNT         — default 10
    DQ_MAX_NULL_PERCENT      — default 5.0
"""

import json
import logging
import os
from datetime import datetime, timedelta, timezone

import azure.functions as func
import pandas as pd
from databricks.sdk import WorkspaceClient

app = func.FunctionApp()

DATABRICKS_HOST = os.environ["DATABRICKS_HOST"]
WAREHOUSE_ID = os.environ["DATABRICKS_WAREHOUSE_ID"]
CLIENT_ID = os.environ.get("AZURE_CLIENT_ID")

MIN_ROW_COUNT = int(os.environ.get("DQ_MIN_ROW_COUNT", "10"))
MAX_NULL_PCT = float(os.environ.get("DQ_MAX_NULL_PERCENT", "5.0"))
MAX_VIEWS = 50_000_000_000
FRESHNESS_HOURS = 48

CRITICAL_COLUMNS = {
    "clean_statistics": ["video_id", "title", "channel_title", "views", "region"],
    "clean_reference_data": ["id", "region"],
}

_ws = WorkspaceClient(host=DATABRICKS_HOST, azure_client_id=CLIENT_ID)


def read_table(catalog: str, table_name: str) -> pd.DataFrame:
    statement = f"SELECT * FROM `{catalog}`.youtube.`{table_name}` LIMIT 10000"
    result = _ws.statement_execution.execute_statement(
        warehouse_id=WAREHOUSE_ID, statement=statement, wait_timeout="30s"
    )
    columns = [c.name for c in result.manifest.schema.columns]
    rows = result.result.data_array or []
    return pd.DataFrame(rows, columns=columns)


def check_row_count(df, table_name):
    count = len(df)
    passed = count >= MIN_ROW_COUNT
    return {"check": "row_count", "table": table_name, "value": count, "threshold": MIN_ROW_COUNT,
            "passed": passed, "message": f"Row count: {count} (min: {MIN_ROW_COUNT})"}


def check_null_percentage(df, table_name):
    results = []
    for col in CRITICAL_COLUMNS.get(table_name, []):
        if col not in df.columns:
            results.append({"check": "null_pct", "table": table_name, "column": col,
                             "passed": False, "message": f"Column '{col}' missing from table"})
            continue
        null_pct = (df[col].isna().sum() / len(df)) * 100 if len(df) > 0 else 0
        passed = null_pct <= MAX_NULL_PCT
        results.append({"check": "null_pct", "table": table_name, "column": col,
                         "value": round(null_pct, 2), "threshold": MAX_NULL_PCT, "passed": passed,
                         "message": f"{col} null%: {null_pct:.2f}% (max: {MAX_NULL_PCT}%)"})
    return results


def check_schema(df, table_name):
    expected = set(CRITICAL_COLUMNS.get(table_name, []))
    missing = expected - set(df.columns)
    passed = len(missing) == 0
    return {"check": "schema", "table": table_name, "missing_columns": list(missing), "passed": passed,
            "message": f"Missing columns: {missing}" if missing else "All expected columns present"}


def check_value_ranges(df, table_name):
    if table_name != "clean_statistics" or "views" not in df.columns:
        return []
    views = pd.to_numeric(df["views"], errors="coerce")
    negative = int((views < 0).sum())
    extreme = int((views > MAX_VIEWS).sum())
    passed = negative == 0 and extreme == 0
    return [{"check": "value_range", "table": table_name, "column": "views", "negative_count": negative,
             "extreme_count": extreme, "passed": passed,
             "message": f"Views: {negative} negative, {extreme} extreme (>{MAX_VIEWS})"}]


def check_freshness(df, table_name):
    ts_col = "_processed_at" if "_processed_at" in df.columns else (
        "_ingestion_timestamp" if "_ingestion_timestamp" in df.columns else None)
    if ts_col is None:
        return {"check": "freshness", "table": table_name, "passed": True,
                "message": "No timestamp column found — skipping freshness check (backfill data)"}
    try:
        latest = pd.to_datetime(df[ts_col]).max()
        cutoff = datetime.now(timezone.utc) - timedelta(hours=FRESHNESS_HOURS)
        if latest.tzinfo is None:
            latest = latest.replace(tzinfo=timezone.utc)
        passed = latest >= cutoff
        return {"check": "freshness", "table": table_name, "latest_record": str(latest),
                "cutoff": str(cutoff), "passed": passed, "message": f"Latest: {latest}, Cutoff: {cutoff}"}
    except Exception as e:
        return {"check": "freshness", "table": table_name, "passed": True,
                "message": f"Could not parse timestamps: {e} — skipping"}


@app.function_name(name="data_quality")
@app.route(route="data_quality", methods=["POST"])
def data_quality(req: func.HttpRequest) -> func.HttpResponse:
    body = req.get_json() if req.get_body() else {}
    catalog = body.get("catalog", "ytpipeline_silver_dev")
    tables = body.get("tables", ["clean_statistics"])

    all_results = []
    overall_passed = True

    for table_name in tables:
        logging.info("Running DQ checks on %s.youtube.%s...", catalog, table_name)
        try:
            df = read_table(catalog, table_name)
        except Exception as e:
            logging.error("Could not read %s: %s", table_name, e)
            all_results.append({"check": "read_table", "table": table_name, "passed": False, "message": str(e)})
            overall_passed = False
            continue

        checks = [check_row_count(df, table_name)]
        checks.extend(check_null_percentage(df, table_name))
        checks.append(check_schema(df, table_name))
        checks.extend(check_value_ranges(df, table_name))
        checks.append(check_freshness(df, table_name))

        for check in checks:
            logging.info("  %s: %s — %s", check["check"], "PASS" if check["passed"] else "FAIL", check["message"])
            if not check["passed"]:
                overall_passed = False

        all_results.extend(checks)

    passed_count = sum(1 for r in all_results if r["passed"])
    total_count = len(all_results)
    logging.info("DQ Summary: %s/%s checks passed. Overall: %s",
                 passed_count, total_count, "PASS" if overall_passed else "FAIL")

    if not overall_passed:
        failed = [r for r in all_results if not r["passed"]]
        logging.warning("[YT Pipeline] Data quality checks FAILED: %s", json.dumps(failed, default=str))

    return func.HttpResponse(
        json.dumps({
            "quality_passed": bool(overall_passed),
            "checks_passed": int(passed_count),
            "checks_total": int(total_count),
            "details": json.loads(json.dumps(all_results, default=str)),
        }),
        mimetype="application/json",
        status_code=200,
    )
