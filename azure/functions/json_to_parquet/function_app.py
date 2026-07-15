"""
Azure Function: JSON Reference Data -> Silver Layer (Parquet)
────────────────────────────────────────────────────────────
Migrated from lambdas/json_to_parquet/lambda_function.py. Instead of an
S3-event trigger firing once per uploaded file, this is invoked once per
pipeline run by ADF (TransformReferenceData activity) after ingestion
completes, and processes every region's category JSON written for
today's date partition — same idempotent "overwrite partition" semantics
as the original.

Environment Variables:
    STORAGE_ACCOUNT_DFS_ENDPOINT — ADLS Gen2 dfs endpoint
    BRONZE_CONTAINER             — Bronze filesystem name
    SILVER_CONTAINER             — Silver filesystem name
    YOUTUBE_REGIONS              — Comma-separated region codes
    AZURE_CLIENT_ID              — user-assigned managed identity client ID
"""

import io
import json
import logging
import os
from datetime import datetime, timezone

import azure.functions as func
import pandas as pd
from azure.identity import ManagedIdentityCredential
from azure.storage.filedatalake import DataLakeServiceClient

app = func.FunctionApp()

DFS_ENDPOINT = os.environ["STORAGE_ACCOUNT_DFS_ENDPOINT"]
BRONZE_CONTAINER = os.environ.get("BRONZE_CONTAINER", "bronze")
SILVER_CONTAINER = os.environ.get("SILVER_CONTAINER", "silver")
REGIONS = os.environ.get("YOUTUBE_REGIONS", "US,GB,CA,DE,FR,IN,JP,KR,MX,RU").split(",")
CLIENT_ID = os.environ.get("AZURE_CLIENT_ID")

_credential = ManagedIdentityCredential(client_id=CLIENT_ID)
_dfs_client = DataLakeServiceClient(account_url=DFS_ENDPOINT, credential=_credential)


def read_json_from_bronze(path: str) -> dict:
    fs_client = _dfs_client.get_file_system_client(BRONZE_CONTAINER)
    file_client = fs_client.get_file_client(path)
    downloader = file_client.download_file()
    return json.loads(downloader.readall().decode("utf-8"))


def validate_category_data(df: pd.DataFrame) -> pd.DataFrame:
    if df.empty:
        raise ValueError("Empty DataFrame — no category items found")

    required_cols = {"id", "snippet.title"}
    missing = required_cols - set(df.columns)
    if missing:
        logging.warning("Missing expected columns: %s. Available: %s", missing, set(df.columns))

    before = len(df)
    if "id" in df.columns:
        df = df.drop_duplicates(subset=["id"], keep="last")
    if before != len(df):
        logging.info("  Removed %s duplicate categories", before - len(df))

    return df


def write_parquet_to_silver(df: pd.DataFrame, region: str):
    fs_client = _dfs_client.get_file_system_client(SILVER_CONTAINER)
    path = f"youtube/reference_data/region={region}/data.parquet"
    buffer = io.BytesIO()
    df.to_parquet(buffer, engine="pyarrow", compression="snappy", index=False)
    buffer.seek(0)
    file_client = fs_client.create_file(path)
    file_client.upload_data(buffer.read(), overwrite=True)  # overwrite = idempotent per region


@app.function_name(name="json_to_parquet")
@app.route(route="json_to_parquet", methods=["POST"])
def json_to_parquet(req: func.HttpRequest) -> func.HttpResponse:
    date_partition = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    processed, errors = [], []

    for region in REGIONS:
        region = region.strip().lower()
        key = f"youtube/raw_statistics_reference_data/region={region}/date={date_partition}/{region}_category_id.json"

        try:
            logging.info("Processing: %s/%s", BRONZE_CONTAINER, key)
            raw_data = read_json_from_bronze(key)

            if "items" in raw_data and isinstance(raw_data["items"], list):
                df = pd.json_normalize(raw_data["items"])
            else:
                df = pd.json_normalize(raw_data)

            df = validate_category_data(df)
            df["_ingestion_timestamp"] = datetime.now(timezone.utc).isoformat()
            df["_source_file"] = key
            df["region"] = region

            write_parquet_to_silver(df, region)
            logging.info("  Written to Silver: region=%s (%s rows)", region, len(df))
            processed.append({"key": key, "region": region, "rows": len(df)})
        except Exception as e:
            logging.error("Error processing %s: %s", region, e, exc_info=True)
            errors.append({"key": key, "error": str(e)})

    if errors:
        logging.warning("[YT Pipeline] Silver reference transform failed: %s", json.dumps(errors))

    return func.HttpResponse(
        json.dumps({"statusCode": 200, "processed": processed, "errors": errors}),
        mimetype="application/json",
        status_code=200,
    )
