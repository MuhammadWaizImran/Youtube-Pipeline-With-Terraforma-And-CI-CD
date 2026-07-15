# Architecture — YouTube Trending Data Pipeline (Azure)

## 1. Data flow (pipeline)

```mermaid
flowchart LR
    subgraph Source
        YT["YouTube Data API v3"]
    end

    subgraph Bronze["Bronze Layer — ADLS Gen2 (raw)"]
        BRZ[("bronze container\nraw JSON, region/date/hour partitioned")]
    end

    subgraph Silver["Silver Layer — Unity Catalog (cleansed)"]
        SLV_STATS[("clean_statistics")]
        SLV_REF[("clean_reference_data")]
    end

    subgraph Gold["Gold Layer — Unity Catalog (analytics)"]
        G1[("trending_analytics")]
        G2[("channel_analytics")]
        G3[("category_analytics")]
    end

    INGEST["Azure Function\nyoutube_api_ingestion"]
    REFXFORM["Azure Function\njson_to_parquet"]
    B2S["Databricks Job\nbronze_to_silver_statistics.py"]
    DQ["Azure Function\ndata_quality\n(gate)"]
    S2G["Databricks Job\nsilver_to_gold_analytics.py"]
    SQLWH["Databricks SQL Warehouse\n(Athena replacement)"]
    ALERT["Azure Monitor\nAction Group (email)"]

    YT -->|"trending videos + categories"| INGEST
    INGEST -->|"raw JSON"| BRZ
    BRZ --> REFXFORM --> SLV_REF
    BRZ --> B2S --> SLV_STATS

    SLV_STATS --> DQ
    SLV_REF --> DQ
    DQ -- "quality_passed = true" --> S2G
    DQ -- "quality_passed = false" --> ALERT

    S2G --> G1
    S2G --> G2
    S2G --> G3

    G1 & G2 & G3 --> SQLWH
    S2G -.->|"run outcome"| ALERT

    style ALERT fill:#7a1f1f,color:#fff
    style DQ fill:#5a4a1f,color:#fff
```

Orchestrated by **Azure Data Factory** (`azure/data_factory/pipeline_definition.json`), triggered every 6 hours — mirrors `step_functions/pipeline_orchestation.json` from the AWS version, including the DQ gate that short-circuits Gold aggregation.

## 2. Azure resource topology

```mermaid
flowchart TB
    subgraph RG["Resource Group: rg-ytpipeline-dev"]
        direction TB

        subgraph StorageL["Storage layer"]
            ADLS["ADLS Gen2\nstytpipelinedev...\nbronze / silver / gold / scripts"]
        end

        subgraph SecurityL["Security layer"]
            KV["Key Vault\nkv-ytpipeline-dev\n(YouTube API key)"]
            ID_FUNC["Managed Identity\nid-ytpipeline-functions-dev"]
            ID_ADF["Managed Identity\nid-ytpipeline-adf-dev"]
            ID_DBX["Managed Identity\nid-ytpipeline-databricks-dev"]
        end

        subgraph ComputeL["Compute layer"]
            FUNCS["3x Azure Functions\ningestion / json-to-parquet / data-quality"]
            DBW["Databricks Workspace\ndbw-ytpipeline-dev"]
            DBAC["Access Connector\ndbac-ytpipeline-dev"]
            UC["Unity Catalog\n3 catalogs: bronze / silver / gold"]
            SQLWH2["SQL Warehouse\nytpipeline-dev-analytics"]
        end

        subgraph OrchL["Orchestration layer"]
            ADF["Data Factory\nadf-ytpipeline-dev\n+ 6h schedule trigger"]
        end

        subgraph MonL["Monitoring layer"]
            LAW["Log Analytics\nlog-ytpipeline-dev"]
            AG["Action Group\nag-ytpipeline-dev (email)"]
        end
    end

    ID_FUNC -.->|"RBAC: Blob Data Contributor"| ADLS
    ID_ADF -.->|"RBAC: Blob Data Contributor"| ADLS
    ID_DBX -.->|"RBAC: Blob Data Contributor"| ADLS
    ID_FUNC -.->|"RBAC: Secrets User"| KV
    FUNCS -->|"UserAssigned identity"| ID_FUNC
    ADF -->|"UserAssigned identity"| ID_ADF
    DBAC -->|"SystemAssigned identity"| ADLS
    DBW --- DBAC
    DBW --- UC
    DBW --- SQLWH2
    ADF -->|"AzureFunctionActivity"| FUNCS
    ADF -->|"DatabricksSparkPython"| DBW
    ADF -->|"metric alert on run failure/success"| AG
    FUNCS -.->|"logs"| LAW
    DBW -.->|"logs"| LAW
```

## 3. Terraform module / state graph

Each box is an **independent Terraform state file** — this is what makes a
one-module change never touch another module's resources (see
`azure/README.md` §"Why a small change doesn't rebuild everything").

```mermaid
flowchart LR
    BOOT["bootstrap\n(tfstate backend\nstorage account)"]:::boot
    STOR["storage"]:::done
    SEC["security"]:::done
    MON["monitoring"]:::done
    DBX["databricks"]:::done
    FUNC["functions"]:::blocked
    ADFm["data-factory"]:::pending

    BOOT -.->|"provides backend for all"| STOR
    STOR --> SEC
    STOR --> MON
    STOR --> DBX
    SEC --> FUNC
    MON --> FUNC
    DBX --> FUNC
    SEC --> ADFm
    MON --> ADFm
    DBX --> ADFm
    FUNC -->|"function host keys"| ADFm

    classDef done fill:#1f5a2e,color:#fff
    classDef blocked fill:#7a1f1f,color:#fff
    classDef pending fill:#5a4a1f,color:#fff
    classDef boot fill:#333,color:#fff
```

**Legend:** 🟢 deployed and live · 🔴 blocked (App Service quota) · 🟡 pending (needs `functions` first) · ⚫ one-time bootstrap

## 4. CI/CD — why a small change doesn't rebuild everything

```mermaid
flowchart TD
    PR["Pull Request"] -->|"paths-filter"| PLAN["terraform-plan.yml\n(only changed module(s))"]
    PLAN -->|"posts plan diff"| REVIEW["PR review"]
    REVIEW -->|"merge to main"| APPLY["terraform-apply.yml\n(only changed module(s),\ndependency-ordered)"]

    CODE1["Function code change"] -->|"paths-filter"| FDEPLOY["functions-deploy.yml\n(az functionapp deploy)"]
    CODE2["Databricks job code change"] -->|"paths-filter"| DDEPLOY["databricks-deploy.yml\n(Databricks CLI fs cp)"]

    FDEPLOY -.->|"never calls"| APPLY
    DDEPLOY -.->|"never calls"| APPLY

    style FDEPLOY fill:#1f5a2e,color:#fff
    style DDEPLOY fill:#1f5a2e,color:#fff
```

Code-only changes (the majority of day-to-day edits) route through the
green paths and **never invoke `terraform apply`** — infrastructure state
is untouched.

## 5. Current deployment status

| Layer | Terraform module | Status |
|---|---|---|
| State backend | `bootstrap` | ✅ Live (`rg-ytpipeline-tfstate`) |
| Data lake | `storage` | ✅ Live |
| Identity/secrets | `security` | ✅ Live |
| Observability | `monitoring` | ✅ Live |
| Spark/SQL | `databricks` | ✅ Live (3 Unity Catalog catalogs, SQL Warehouse) |
| Compute (Functions) | `functions` | 🔴 Blocked — subscription's App Service "Total VMs" quota is 0, needs a support-ticket quota increase |
| Orchestration | `data-factory` | 🟡 Pending — needs `functions` deployed first (function host keys) |
