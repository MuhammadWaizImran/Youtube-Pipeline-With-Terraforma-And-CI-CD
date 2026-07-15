"""
Databricks Job: Silver -> Gold (Analytics Aggregations)
──────────────────────────────────────────────────────────
Migrated from glue_jobs/silver_to_gold_analytics.py. Same three Gold
tables and aggregation logic as the AWS Glue job; reads/writes go through
Unity Catalog instead of the Glue Data Catalog + S3.

Job Parameters:
    --silver_catalog   — Unity Catalog catalog for Silver
    --gold_catalog     — Unity Catalog catalog for Gold
"""

import argparse

from pyspark.sql import SparkSession, functions as F, Window

parser = argparse.ArgumentParser()
parser.add_argument("--silver_catalog", required=True)
parser.add_argument("--gold_catalog", required=True)
args = parser.parse_args()

spark = SparkSession.builder.getOrCreate()
spark.conf.set("spark.sql.sources.partitionOverwriteMode", "dynamic")

SILVER_CATALOG = args.silver_catalog
GOLD_CATALOG = args.gold_catalog

# ── Read Silver Tables ──────────────────────────────────────────────────────
print("Reading Silver layer tables...")

stats_df = spark.table(f"`{SILVER_CATALOG}`.youtube.clean_statistics")
print(f"Statistics records: {stats_df.count()}")

print("Attempting to read Silver reference data for category names...")
try:
    ref_df = spark.table(f"`{SILVER_CATALOG}`.youtube.clean_reference_data")

    category_lookup = None
    if "id" in ref_df.columns and "snippet.title" in ref_df.columns:
        category_lookup = ref_df.select(
            F.col("id").cast("long").alias("category_id"),
            F.col("`snippet.title`").alias("category_name"),
        ).dropDuplicates(["category_id"])
    elif "id" in ref_df.columns and "snippet_title" in ref_df.columns:
        category_lookup = ref_df.select(
            F.col("id").cast("long").alias("category_id"),
            F.col("snippet_title").alias("category_name"),
        ).dropDuplicates(["category_id"])
    else:
        print(f"Could not find expected category title columns. Columns found: {ref_df.columns}")

    if category_lookup is not None:
        print(f"Category lookup entries: {category_lookup.count()}")
        if "category_id" in stats_df.columns:
            stats_df = stats_df.withColumn("category_id", F.col("category_id").cast("long"))
        stats_df = stats_df.join(F.broadcast(category_lookup), on="category_id", how="left")
except Exception as e:
    print(f"Could not load reference data: {e}. Proceeding without category names.")

if "category_name" not in stats_df.columns:
    stats_df = stats_df.withColumn("category_name", F.lit("Unknown"))
else:
    stats_df = stats_df.fillna("Unknown", subset=["category_name"])

# ══════════════════════════════════════════════════════════════════════════
# GOLD TABLE 1: Trending Analytics
# ══════════════════════════════════════════════════════════════════════════
print("Building Gold: trending_analytics...")

trending = stats_df.groupBy("region", "trending_date_parsed").agg(
    F.count("video_id").alias("total_videos"),
    F.sum("views").alias("total_views"),
    F.sum("likes").alias("total_likes"),
    F.sum("dislikes").alias("total_dislikes"),
    F.sum("comment_count").alias("total_comments"),
    F.avg("views").alias("avg_views_per_video"),
    F.avg("like_ratio").alias("avg_like_ratio"),
    F.avg("engagement_rate").alias("avg_engagement_rate"),
    F.max("views").alias("max_views"),
    F.countDistinct("channel_title").alias("unique_channels"),
    F.countDistinct("category_id").alias("unique_categories"),
).withColumn("_aggregated_at", F.current_timestamp())

(
    trending.write.format("delta").mode("overwrite").partitionBy("region")
    .saveAsTable(f"`{GOLD_CATALOG}`.youtube.trending_analytics")
)
print(f"  Written {trending.count()} rows -> {GOLD_CATALOG}.youtube.trending_analytics")

# ══════════════════════════════════════════════════════════════════════════
# GOLD TABLE 2: Channel Analytics
# ══════════════════════════════════════════════════════════════════════════
print("Building Gold: channel_analytics...")

channel = stats_df.groupBy("channel_title", "region").agg(
    F.countDistinct("video_id").alias("total_videos"),
    F.sum("views").alias("total_views"),
    F.sum("likes").alias("total_likes"),
    F.sum("comment_count").alias("total_comments"),
    F.avg("views").alias("avg_views_per_video"),
    F.avg("engagement_rate").alias("avg_engagement_rate"),
    F.max("views").alias("peak_views"),
    F.count("trending_date_parsed").alias("times_trending"),
    F.min("trending_date_parsed").alias("first_trending"),
    F.max("trending_date_parsed").alias("last_trending"),
    F.collect_set("category_name").alias("categories"),
)

window_rank = Window.partitionBy("region").orderBy(F.col("total_views").desc())
channel = channel.withColumn("rank_in_region", F.row_number().over(window_rank))
channel = channel.withColumn("_aggregated_at", F.current_timestamp())

(
    channel.write.format("delta").mode("overwrite").partitionBy("region")
    .saveAsTable(f"`{GOLD_CATALOG}`.youtube.channel_analytics")
)
print(f"  Written {channel.count()} rows -> {GOLD_CATALOG}.youtube.channel_analytics")

# ══════════════════════════════════════════════════════════════════════════
# GOLD TABLE 3: Category Analytics
# ══════════════════════════════════════════════════════════════════════════
print("Building Gold: category_analytics...")

category = stats_df.groupBy("category_name", "category_id", "region", "trending_date_parsed").agg(
    F.count("video_id").alias("video_count"),
    F.sum("views").alias("total_views"),
    F.sum("likes").alias("total_likes"),
    F.sum("comment_count").alias("total_comments"),
    F.avg("engagement_rate").alias("avg_engagement_rate"),
    F.countDistinct("channel_title").alias("unique_channels"),
)

window_total = Window.partitionBy("region", "trending_date_parsed")
category = category.withColumn(
    "view_share_pct",
    F.round(F.col("total_views") / F.sum("total_views").over(window_total) * 100, 2),
)
category = category.withColumn("_aggregated_at", F.current_timestamp())

(
    category.write.format("delta").mode("overwrite").partitionBy("region")
    .saveAsTable(f"`{GOLD_CATALOG}`.youtube.category_analytics")
)
print(f"  Written {category.count()} rows -> {GOLD_CATALOG}.youtube.category_analytics")

print("Gold layer build complete.")
