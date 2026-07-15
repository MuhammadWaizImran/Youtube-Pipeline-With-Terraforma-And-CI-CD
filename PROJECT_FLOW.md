# YouTube Trending Data Pipeline — Project Flow

One YouTube trending-video ETL pipeline, implemented twice (AWS-native ➜ Azure port),
both wrapped in modular Terraform + GitHub Actions CI/CD with the same core rule:

> 🔹 **small change → only that block redeploys**
> 🔸 **big/structural change → the affected chain redeploys, nothing else**

---

## 1️⃣ Data Flow (same shape on both clouds)

```
 ┌──────────────┐
 │ YouTube API  │  🌐 source
 │   v3         │
 └──────┬───────┘
        │  fetch trending videos + categories
        ▼
 ┌──────────────────────────┐
 │   🥉 BRONZE (raw)         │  S3 / ADLS Gen2 — raw JSON, partitioned
 │   region / date / hour   │      by region=xx/date=yyyy-mm-dd/hour=hh
 └──────┬───────────┬───────┘
        │           │
        ▼           ▼
 ┌─────────────┐ ┌───────────────────┐
 │ ref-data    │ │ bronze→silver ETL │   ⚙️ parallel branch
 │ transform   │ │ (Glue / Databricks)│
 └──────┬──────┘ └─────────┬──────────┘
        │                  │
        ▼                  ▼
 ┌──────────────────────────────────┐
 │   🥈 SILVER (cleansed)            │  clean_statistics + clean_reference_data
 └──────────────┬────────────────────┘
                ▼
        ┌───────────────┐
        │  ✅ DQ GATE    │  row count, null %, schema, freshness
        └───┬───────┬────┘
    passed  │       │  failed
            ▼       ▼
   ┌────────────┐  ┌─────────────────┐
   │ silver→gold │  │ 🔔 alert (SNS /  │  ⛔ Gold step SKIPPED
   │ aggregation │  │ Action Group)    │
   └──────┬──────┘  └─────────────────┘
          ▼
 ┌──────────────────────────────────┐
 │   🥇 GOLD (analytics)             │  trending_analytics · channel_analytics
 │                                    │  category_analytics
 └──────────────┬────────────────────┘
                ▼
        ┌───────────────┐
        │ 🔎 Athena /    │  ad-hoc queries, dashboards
        │ Databricks SQL │
        └───────────────┘

 Orchestrated by: Step Functions (AWS) / Data Factory (Azure)
 Triggered by:    EventBridge (AWS) / Schedule Trigger (Azure) — rate(6 hours)
```

---

## 2️⃣ Infrastructure — module dependency chain

Each 📦 is an **independent Terraform state file**. Arrows = "reads this
module's outputs via remote state" — NOT "gets redeployed together."

```
AWS                                  Azure
────────────────────────────────    ────────────────────────────────
📦 bootstrap (tfstate backend)       📦 bootstrap (tfstate backend)
        │                                    │
        ▼                                    ▼
📦 storage (S3 x4)                   📦 storage (ADLS Gen2 x4)
        │                                    │
   ┌────┴────┐                          ┌────┴──────┬─────────┐
   ▼         ▼                          ▼            ▼         ▼
📦 security 📦 monitoring          📦 security  📦 monitoring 📦 databricks
   │  (IAM)   (SNS/CW)                │ (KeyVault)  (LogAW/AG)   (workspace+UC)
   └────┬────┘                        └──────┬──────┴─────┬─────┘
        ▼                                    ▼             │
   📦 glue (Catalog+Jobs+Athena)        📦 functions (3x)   │
        │                                    │              │
        ▼                                    └──────┬───────┘
   📦 lambda (3x functions)                          ▼
        │                                    📦 data-factory (pipeline + triggers)
        ▼
   📦 orchestration (Step Functions + 🔁 EventBridge schedule)
        ▲
        └── 🔹 changing ONLY schedule_expression here
            touches ONLY this 📦 — everything above is untouched
```

**Current live status:**

| | AWS | Azure |
|---|---|---|
| storage | ✅ | ✅ |
| security | ✅ | ✅ |
| monitoring | ✅ | ✅ |
| glue / databricks | ✅ | ✅ |
| lambda / functions | ✅ | 🔴 blocked (quota) |
| orchestration / data-factory | ✅ | 🟡 pending |

---

## 3️⃣ CI/CD — what runs when

```
                      ┌─────────────────────┐
                      │  git push to main    │
                      └──────────┬────────────┘
                                 │
              ┌──────────────────┼───────────────────┐
              ▼                  ▼                    ▼
   changed: lambdas/**   changed: glue_jobs/**   changed: aws/terraform/**
   or data_quality/**                             (or azure/terraform/**)
              │                  │                    │
              ▼                  ▼                    ▼
   🟢 *-deploy.yml       🟢 *-deploy.yml        🟡 *-terraform-apply.yml
   (aws lambda           (aws s3 cp /           (path-filtered,
    update-function-      databricks fs cp)      dependency-ordered,
    code)                                        ONLY changed 📦 module)
              │                  │                    │
              ▼                  ▼                    ▼
     Terraform state       Terraform state       Only that module's
     NEVER touched          NEVER touched         state file changes
```

🟢 = code-only path, bypasses Terraform entirely
🟡 = infra path, but isolated to the one changed module (path-filter + per-module state)

---

## 4️⃣ Legend

| Symbol | Meaning |
|---|---|
| 🥉🥈🥇 | Bronze / Silver / Gold medallion layers |
| 📦 | Independent Terraform state (a "module") |
| ✅ | DQ gate / live & verified |
| 🔴 | Blocked |
| 🟡 | Pending / infra-path CI |
| 🟢 | Code-only CI path (no Terraform) |
| 🔁 | Schedule / recurring trigger |
| 🔔 | Alert (SNS Action Group / email) |
| ⛔ | Short-circuit (pipeline step skipped) |

---

## 5️⃣ One-line summary

**YouTube API → Bronze → (parallel: ref-data + Silver ETL) → DQ gate →
Gold → SQL query layer**, orchestrated on a 6-hour schedule, with
**infrastructure split into 6–7 independently-stated Terraform modules per
cloud** so that a code edit or a single-resource tweak (like the
EventBridge schedule) redeploys only the one relevant piece — never the
whole stack.
