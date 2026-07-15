"""
YT Trending Analytics Dashboard
────────────────────────────────
Reads the pipeline's Gold-layer tables (trending_analytics,
channel_analytics, category_analytics) straight from Athena and
auto-refreshes on a timer to give a "live" feel.

IMPORTANT: the underlying pipeline is a scheduled BATCH job (currently
every 5 minutes via EventBridge — see aws/terraform/envs/dev/orchestration),
not a real-time stream. This dashboard polls Athena on an interval and
shows exactly when the data was last refreshed, rather than pretending
the numbers are updating continuously between pipeline runs.

Run:
    cd aws/dashboard
    streamlit run streamlit_app.py

Requires AWS credentials in the environment (same ones the aws CLI uses).
"""

import time
from datetime import datetime, timezone

import awswrangler as wr
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
import streamlit as st
from streamlit_autorefresh import st_autorefresh

# ── Config ───────────────────────────────────────────────────────────────────
AWS_REGION = "us-east-1"
GOLD_DATABASE = "yt_data_pipeline_gold_dev"
ATHENA_WORKGROUP = "yt-data-pipeline-dev"

YT_RED = "#FF0000"
YT_DARK = "#0F0F0F"
YT_DARK_SECONDARY = "#181818"
YT_GRAY = "#AAAAAA"
YT_WHITE = "#FFFFFF"

st.set_page_config(
    page_title="YT Trending Analytics",
    page_icon="▶️",
    layout="wide",
    initial_sidebar_state="expanded",
)

# ── YouTube-themed styling ───────────────────────────────────────────────────
st.markdown(
    f"""
    <style>
        .stApp {{
            background-color: {YT_DARK};
            color: {YT_WHITE};
        }}
        section[data-testid="stSidebar"] {{
            background-color: {YT_DARK_SECONDARY};
        }}
        div[data-testid="stMetric"] {{
            background-color: {YT_DARK_SECONDARY};
            border: 1px solid #303030;
            border-radius: 12px;
            padding: 16px 20px;
        }}
        div[data-testid="stMetricLabel"] {{
            color: {YT_GRAY};
        }}
        div[data-testid="stMetricValue"] {{
            color: {YT_WHITE};
        }}
        .yt-badge {{
            display: inline-block;
            background-color: {YT_RED};
            color: white;
            padding: 2px 10px;
            border-radius: 4px;
            font-weight: 700;
            font-size: 0.75rem;
            letter-spacing: 0.05em;
        }}
        .yt-live-dot {{
            height: 10px;
            width: 10px;
            background-color: #2ecc71;
            border-radius: 50%;
            display: inline-block;
            margin-right: 6px;
            animation: pulse 1.5s infinite;
        }}
        @keyframes pulse {{
            0% {{ opacity: 1; }}
            50% {{ opacity: 0.3; }}
            100% {{ opacity: 1; }}
        }}
        div.stButton > button {{
            background-color: {YT_RED};
            color: white;
            border: none;
            border-radius: 20px;
            font-weight: 600;
        }}
        hr {{ border-color: #303030; }}
    </style>
    """,
    unsafe_allow_html=True,
)

# ── Sidebar controls ─────────────────────────────────────────────────────────
st.sidebar.markdown("## ▶️ YT Trending Analytics")
st.sidebar.caption("AWS S3 → Lambda → Glue → Athena pipeline")

refresh_seconds = st.sidebar.slider(
    "Auto-refresh interval (seconds)", min_value=15, max_value=300, value=30, step=15
)
region_filter = st.sidebar.selectbox(
    "Region", ["All", "us", "gb", "ca", "in", "de", "fr", "jp", "kr", "mx", "ru"]
)
manual_refresh = st.sidebar.button("🔄 Refresh now")

st.sidebar.markdown("---")
st.sidebar.markdown(
    """
    <span class="yt-badge">BATCH, NOT STREAMING</span>
    <p style="color:#AAAAAA; font-size:0.85rem; margin-top:8px;">
    Source data updates every time the Step Functions pipeline runs
    (EventBridge schedule). This dashboard just polls Athena on the
    interval above — it does not receive a live event stream.
    </p>
    """,
    unsafe_allow_html=True,
)

st_autorefresh(interval=refresh_seconds * 1000, key="dashboard_autorefresh")

# ── Data loading ─────────────────────────────────────────────────────────────
@st.cache_data(ttl=15, show_spinner=False)
def load_table(table_name: str) -> pd.DataFrame:
    query = f'SELECT * FROM "{table_name}"'
    return wr.athena.read_sql_query(
        sql=query,
        database=GOLD_DATABASE,
        workgroup=ATHENA_WORKGROUP,
        boto3_session=None,
        ctas_approach=False,
    )


if manual_refresh:
    load_table.clear()

load_error = None
try:
    trending_df = load_table("trending_analytics")
    channel_df = load_table("channel_analytics")
    category_df = load_table("category_analytics")
except Exception as e:
    load_error = str(e)
    trending_df = channel_df = category_df = pd.DataFrame()

if region_filter != "All":
    if not trending_df.empty:
        trending_df = trending_df[trending_df["region"] == region_filter]
    if not channel_df.empty:
        channel_df = channel_df[channel_df["region"] == region_filter]
    if not category_df.empty:
        category_df = category_df[category_df["region"] == region_filter]

# ── Header ───────────────────────────────────────────────────────────────────
header_col1, header_col2 = st.columns([3, 1])
with header_col1:
    st.markdown(
        f"""
        <h1 style="margin-bottom:0;">
            <span style="color:{YT_RED};">▶</span> YouTube Trending Analytics
        </h1>
        <p style="color:{YT_GRAY}; margin-top:4px;">
            Gold layer — <code>{GOLD_DATABASE}</code> · workgroup
            <code>{ATHENA_WORKGROUP}</code>
        </p>
        """,
        unsafe_allow_html=True,
    )
with header_col2:
    now = datetime.now(timezone.utc).strftime("%H:%M:%S UTC")
    st.markdown(
        f"""
        <div style="text-align:right; padding-top:20px;">
            <span class="yt-live-dot"></span>
            <span style="color:#2ecc71; font-weight:600;">POLLING</span><br/>
            <span style="color:{YT_GRAY}; font-size:0.85rem;">Last checked: {now}</span>
        </div>
        """,
        unsafe_allow_html=True,
    )

st.markdown("---")

if load_error:
    st.error(
        f"Could not query Athena — check AWS credentials / that the pipeline has "
        f"run at least once.\n\n`{load_error}`"
    )
    st.stop()

if trending_df.empty:
    st.warning("No data in the Gold tables yet — run the Step Functions pipeline first.")
    st.stop()

# ── KPI row ──────────────────────────────────────────────────────────────────
total_videos = int(trending_df["total_videos"].sum())
total_views = int(trending_df["total_views"].sum())
total_channels = int(channel_df["channel_title"].nunique()) if not channel_df.empty else 0
avg_engagement = (
    round(float(trending_df["avg_engagement_rate"].mean()), 3)
    if "avg_engagement_rate" in trending_df.columns
    else 0
)

k1, k2, k3, k4 = st.columns(4)
k1.metric("Total Trending Videos", f"{total_videos:,}")
k2.metric("Total Views", f"{total_views:,}")
k3.metric("Unique Channels", f"{total_channels:,}")
k4.metric("Avg Engagement Rate", f"{avg_engagement}%")

st.markdown("---")

# ── Charts ───────────────────────────────────────────────────────────────────
chart_col1, chart_col2 = st.columns(2)

yt_colorscale = [YT_RED, "#FF6666", "#FF9999", "#FFCCCC", "#282828", "#606060"]

with chart_col1:
    st.subheader("Views by Region")
    by_region = (
        trending_df.groupby("region", as_index=False)["total_views"]
        .sum()
        .sort_values("total_views", ascending=False)
    )
    fig = px.bar(
        by_region,
        x="region",
        y="total_views",
        color="total_views",
        color_continuous_scale=["#3a0000", YT_RED],
    )
    fig.update_layout(
        plot_bgcolor=YT_DARK_SECONDARY,
        paper_bgcolor=YT_DARK,
        font_color=YT_WHITE,
        coloraxis_showscale=False,
    )
    st.plotly_chart(fig, use_container_width=True)

with chart_col2:
    st.subheader("Category View Share")
    if not category_df.empty and "view_share_pct" in category_df.columns:
        cat_agg = (
            category_df.groupby("category_name", as_index=False)["view_share_pct"]
            .mean()
            .sort_values("view_share_pct", ascending=False)
            .head(8)
        )
        fig2 = go.Figure(
            data=[
                go.Pie(
                    labels=cat_agg["category_name"],
                    values=cat_agg["view_share_pct"],
                    hole=0.55,
                    marker=dict(colors=yt_colorscale),
                )
            ]
        )
        fig2.update_layout(
            plot_bgcolor=YT_DARK,
            paper_bgcolor=YT_DARK,
            font_color=YT_WHITE,
            showlegend=True,
        )
        st.plotly_chart(fig2, use_container_width=True)
    else:
        st.info("No category data available yet.")

st.markdown("---")

# ── Top channels ─────────────────────────────────────────────────────────────
st.subheader("🏆 Top Channels")
if not channel_df.empty:
    top_channels = channel_df.sort_values("total_views", ascending=False).head(10)
    fig3 = px.bar(
        top_channels,
        x="total_views",
        y="channel_title",
        orientation="h",
        color_discrete_sequence=[YT_RED],
    )
    fig3.update_layout(
        plot_bgcolor=YT_DARK_SECONDARY,
        paper_bgcolor=YT_DARK,
        font_color=YT_WHITE,
        yaxis=dict(autorange="reversed"),
    )
    st.plotly_chart(fig3, use_container_width=True)

    st.dataframe(
        top_channels[
            ["channel_title", "region", "total_videos", "total_views", "avg_engagement_rate", "rank_in_region"]
        ],
        use_container_width=True,
        hide_index=True,
    )
else:
    st.info("No channel data available yet.")

st.markdown("---")

# ── Raw trending table ───────────────────────────────────────────────────────
with st.expander("📊 Raw trending_analytics data"):
    st.dataframe(trending_df, use_container_width=True, hide_index=True)
