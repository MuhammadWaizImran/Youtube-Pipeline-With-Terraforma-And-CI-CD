"""
Databricks Job: Bronze -> Silver (Statistics Data)
────────────────────────────────────────────────────
Migrated from glue_jobs/bronze_to_silver_statistics.py. Same schema
enforcement / cleansing / dedup logic as the AWS Glue job; the only
changes are the runtime (plain SparkSession instead of GlueContext /
DynamicFrame) and the catalog (Unity Catalog three-part names instead of
the Glue Data Catalog).

Job Parameters (passed as CLI args by the ADF DatabricksSparkPython
activity — see azure/data_factory/pipeline_definition.json):
    --bronze_catalog   — Unity Catalog catalog for Bronze (e.g. ytpipeline_bronze_dev)
    --bronze_table     — Bronze statistics table name
    --silver_catalog   — Unity Catalog catalog for Silver
    --silver_table     — Silver statistics table name
"""

import argparse
from datetime import datetime

from pyspark.sql import SparkSession, functions as F, Window
from pyspark.sql.types import BooleanType, LongType, StringType

parser = argparse.ArgumentParser()
parser.add_argument("--bronze_catalog", required=True)
parser.add_argument("--bronze_table", required=True)
parser.add_argument("--silver_catalog", required=True)
parser.add_argument("--silver_table", required=True)
args = parser.parse_args()

spark = SparkSession.builder.getOrCreate()

BRONZE_TABLE = f"`{args.bronze_catalog}`.youtube.`{args.bronze_table}`"
SILVER_TABLE = f"`{args.silver_catalog}`.youtube.`{args.silver_table}`"

print(f"Bronze: {BRONZE_TABLE}")
print(f"Silver: {SILVER_TABLE}")

# ── Step 1: Read from Bronze ────────────────────────────────────────────────
print("Reading from Bronze catalog...")

df = spark.table(BRONZE_TABLE).where("lower(region) in ('ca','gb','us','in')")
initial_count = df.count()
print(f"Bronze records read: {initial_count}")

if initial_count == 0:
    print("No new records to process. Exiting.")
else:
    # ── Step 2: Schema Enforcement ──────────────────────────────────────────
    print("Enforcing schema and casting types...")
    columns = set(df.columns)

    if "snippet.title" in columns or "snippet__title" in columns:
        print("Detected YouTube API format — flattening...")
        df = df.select(
            F.col("id").alias("video_id"),
            F.lit(datetime.utcnow().strftime("%y.%d.%m")).alias("trending_date"),
            (F.col("`snippet.title`") if "snippet.title" in columns else F.col("snippet__title")).alias("title"),
            (F.col("`snippet.channelTitle`") if "snippet.channelTitle" in columns else F.col("snippet__channelTitle")).alias("channel_title"),
            (F.col("`snippet.categoryId`") if "snippet.categoryId" in columns else F.col("snippet__categoryId")).cast(LongType()).alias("category_id"),
            (F.col("`snippet.publishedAt`") if "snippet.publishedAt" in columns else F.col("snippet__publishedAt")).alias("publish_time"),
            (F.col("`snippet.tags`") if "snippet.tags" in columns else F.lit(None).cast(StringType())).alias("tags"),
            (F.col("`statistics.viewCount`") if "statistics.viewCount" in columns else F.col("statistics__viewCount")).cast(LongType()).alias("views"),
            (F.col("`statistics.likeCount`") if "statistics.likeCount" in columns else F.col("statistics__likeCount")).cast(LongType()).alias("likes"),
            (F.col("`statistics.dislikeCount`") if "statistics.dislikeCount" in columns else F.lit(0)).cast(LongType()).alias("dislikes"),
            (F.col("`statistics.commentCount`") if "statistics.commentCount" in columns else F.col("statistics__commentCount")).cast(LongType()).alias("comment_count"),
            (F.col("`snippet.thumbnails.default.url`") if "snippet.thumbnails.default.url" in columns else F.lit(None).cast(StringType())).alias("thumbnail_link"),
            F.lit(False).alias("comments_disabled"),
            F.lit(False).alias("ratings_disabled"),
            F.lit(False).alias("video_error_or_removed"),
            (F.col("`snippet.description`") if "snippet.description" in columns else F.col("snippet__description")).alias("description"),
            F.col("region"),
        )
    else:
        print("Detected Kaggle CSV format — casting types...")
        df = df.select(
            F.col("video_id").cast(StringType()),
            F.col("trending_date").cast(StringType()),
            F.col("title").cast(StringType()),
            F.col("channel_title").cast(StringType()),
            F.col("category_id").cast(LongType()),
            F.col("publish_time").cast(StringType()),
            F.col("tags").cast(StringType()),
            F.col("views").cast(LongType()),
            F.col("likes").cast(LongType()),
            F.col("dislikes").cast(LongType()),
            F.col("comment_count").cast(LongType()),
            F.col("thumbnail_link").cast(StringType()),
            F.col("comments_disabled").cast(BooleanType()),
            F.col("ratings_disabled").cast(BooleanType()),
            F.col("video_error_or_removed").cast(BooleanType()),
            F.col("description").cast(StringType()),
            F.col("region").cast(StringType()),
        )

    # ── Step 3: Data Cleansing ──────────────────────────────────────────────
    print("Cleansing data...")
    df = df.filter(F.col("video_id").isNotNull())
    df = df.withColumn("region", F.lower(F.trim(F.col("region"))))

    df = df.withColumn(
        "trending_date_parsed",
        F.when(
            F.col("trending_date").rlike(r"^\d{2}\.\d{2}\.\d{2}$"),
            F.to_date(F.col("trending_date"), "yy.dd.MM"),
        ).otherwise(F.to_date(F.col("trending_date"))),
    )

    for col_name in ["views", "likes", "dislikes", "comment_count"]:
        df = df.withColumn(col_name, F.coalesce(F.col(col_name), F.lit(0)))

    df = df.withColumn(
        "like_ratio",
        F.when(F.col("views") > 0, F.round(F.col("likes") / F.col("views") * 100, 4)).otherwise(0.0),
    )
    df = df.withColumn(
        "engagement_rate",
        F.when(
            F.col("views") > 0,
            F.round((F.col("likes") + F.col("dislikes") + F.col("comment_count")) / F.col("views") * 100, 4),
        ).otherwise(0.0),
    )

    df = df.withColumn("_processed_at", F.current_timestamp())
    df = df.withColumn("_job_name", F.lit("bronze_to_silver_statistics"))

    # ── Step 4: Deduplication ───────────────────────────────────────────────
    print("Deduplicating...")
    window = Window.partitionBy("video_id", "region", "trending_date_parsed").orderBy(F.col("_processed_at").desc())
    df = df.withColumn("_row_num", F.row_number().over(window)).filter(F.col("_row_num") == 1).drop("_row_num")

    clean_count = df.count()
    print(f"After cleansing & dedup: {clean_count} records (removed {initial_count - clean_count})")

    # ── Step 5: Data Quality Checks (logged, not enforced here — the DQ
    # Function/ADF gate is the enforcement point) ────────────────────────────
    null_counts = {
        c: df.filter(F.col(c).isNull()).count() for c in ["video_id", "title", "channel_title", "views"]
    }
    print(f"  DQ check complete. Null counts: {null_counts}")

    # ── Step 6: Write to Silver Layer (Unity Catalog managed table) ─────────
    # Dynamic partition overwrite = idempotent per-partition write, same
    # semantics as the AWS job's UPDATE_IN_DATABASE Glue sink.
    print(f"Writing to Silver: {SILVER_TABLE}")
    spark.conf.set("spark.sql.sources.partitionOverwriteMode", "dynamic")
    (
        df.write.format("delta")
        .mode("overwrite")
        .partitionBy("region")
        .saveAsTable(SILVER_TABLE)
    )
    print(f"Silver write complete. {clean_count} records written.")
