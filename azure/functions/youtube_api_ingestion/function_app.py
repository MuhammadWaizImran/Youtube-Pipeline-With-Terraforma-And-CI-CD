"""
Azure Function: YouTube Data API Ingestion (Bronze Layer)
───────────────────────────────────────────────────────────
Migrated from lambdas/youtube_api_integstion/lambda_function.py.
Triggered by an ADF AzureFunctionActivity on the pipeline's 6-hour
schedule trigger. Pulls trending videos from the YouTube Data API for
each configured region and writes raw JSON to the Bronze ADLS Gen2
container.

Environment Variables (set by the `functions` Terraform module):
    YOUTUBE_API_KEY               — Key Vault reference, resolved by the platform
    STORAGE_ACCOUNT_DFS_ENDPOINT  — ADLS Gen2 dfs endpoint
    BRONZE_CONTAINER              — Bronze filesystem/container name
    YOUTUBE_REGIONS               — Comma-separated region codes
    AZURE_CLIENT_ID               — user-assigned managed identity client ID
"""

import json
import logging
import os
from datetime import datetime, timezone
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

import azure.functions as func
from azure.identity import ManagedIdentityCredential
from azure.storage.filedatalake import DataLakeServiceClient

app = func.FunctionApp()

API_KEY = os.environ["YOUTUBE_API_KEY"]
DFS_ENDPOINT = os.environ["STORAGE_ACCOUNT_DFS_ENDPOINT"]
BRONZE_CONTAINER = os.environ.get("BRONZE_CONTAINER", "bronze")
REGIONS = os.environ.get("YOUTUBE_REGIONS", "US,GB,CA,DE,FR,IN,JP,KR,MX,RU").split(",")
CLIENT_ID = os.environ.get("AZURE_CLIENT_ID")
API_BASE = "https://www.googleapis.com/youtube/v3"
MAX_RESULTS = 50

_credential = ManagedIdentityCredential(client_id=CLIENT_ID)
_dfs_client = DataLakeServiceClient(account_url=DFS_ENDPOINT, credential=_credential)


def fetch_trending_videos(region_code: str) -> dict:
    params = urlencode({
        "part": "snippet,statistics,contentDetails",
        "chart": "mostPopular",
        "regionCode": region_code,
        "maxResults": MAX_RESULTS,
        "key": API_KEY,
    })
    req = Request(f"{API_BASE}/videos?{params}", headers={"Accept": "application/json"})
    with urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def fetch_video_categories(region_code: str) -> dict:
    params = urlencode({"part": "snippet", "regionCode": region_code, "key": API_KEY})
    req = Request(f"{API_BASE}/videoCategories?{params}", headers={"Accept": "application/json"})
    with urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def write_to_adls(data: dict, path: str):
    fs_client = _dfs_client.get_file_system_client(BRONZE_CONTAINER)
    file_client = fs_client.create_file(path)
    body = json.dumps(data, ensure_ascii=False, indent=2).encode("utf-8")
    file_client.upload_data(body, overwrite=True)
    file_client.set_metadata({
        "ingestion_timestamp": datetime.now(timezone.utc).isoformat(),
        "source": "youtube_data_api_v3",
    })


@app.function_name(name="youtube_api_ingestion")
@app.route(route="youtube_api_ingestion", methods=["POST"])
def youtube_api_ingestion(req: func.HttpRequest) -> func.HttpResponse:
    now = datetime.now(timezone.utc)
    date_partition = now.strftime("%Y-%m-%d")
    hour_partition = now.strftime("%H")
    ingestion_id = now.strftime("%Y%m%d_%H%M%S")

    results = {"success": [], "failed": []}

    for region in REGIONS:
        region = region.strip().lower()
        logging.info("Processing region: %s", region)

        try:
            trending_data = fetch_trending_videos(region)
            video_count = len(trending_data.get("items", []))
            trending_data["_pipeline_metadata"] = {
                "ingestion_id": ingestion_id,
                "region": region,
                "ingestion_timestamp": now.isoformat(),
                "video_count": video_count,
                "source": "youtube_data_api_v3",
            }
            path = (
                f"youtube/raw_statistics/region={region}/"
                f"date={date_partition}/hour={hour_partition}/{ingestion_id}.json"
            )
            write_to_adls(trending_data, path)
            logging.info("  Wrote %s videos -> %s/%s", video_count, BRONZE_CONTAINER, path)
        except (HTTPError, URLError) as e:
            logging.error("  API error for %s trending: %s", region, e)
            results["failed"].append({"region": region, "type": "trending", "error": str(e)})
            continue
        except Exception as e:
            logging.error("  Unexpected error for %s trending: %s", region, e)
            results["failed"].append({"region": region, "type": "trending", "error": str(e)})
            continue

        try:
            category_data = fetch_video_categories(region)
            category_data["_pipeline_metadata"] = {
                "ingestion_id": ingestion_id,
                "region": region,
                "ingestion_timestamp": now.isoformat(),
                "source": "youtube_data_api_v3",
            }
            ref_path = (
                f"youtube/raw_statistics_reference_data/region={region}/"
                f"date={date_partition}/{region}_category_id.json"
            )
            write_to_adls(category_data, ref_path)
            logging.info("  Wrote categories -> %s/%s", BRONZE_CONTAINER, ref_path)
        except (HTTPError, URLError) as e:
            logging.error("  API error for %s categories: %s", region, e)
            results["failed"].append({"region": region, "type": "categories", "error": str(e)})
            continue

        results["success"].append(region)

    summary = (
        f"Ingestion {ingestion_id} complete. "
        f"Success: {len(results['success'])}/{len(REGIONS)} regions. "
        f"Failed: {len(results['failed'])}."
    )
    logging.info(summary)

    # Partial-region failures are surfaced in the response body (and in
    # Application Insights via the log lines above) rather than raised as
    # an exception, so ADF still marks the activity Succeeded and downstream
    # DQ checks decide whether the run is healthy enough to continue —
    # matching the original Lambda's "best-effort per region" behavior.
    if results["failed"]:
        logging.warning("[YT Pipeline] Ingestion partial failure — %s", json.dumps(results))

    return func.HttpResponse(
        json.dumps({"statusCode": 200, "ingestion_id": ingestion_id, "results": results}),
        mimetype="application/json",
        status_code=200,
    )
