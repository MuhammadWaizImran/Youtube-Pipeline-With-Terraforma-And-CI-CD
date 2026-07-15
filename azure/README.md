# YouTube Trending Data Pipeline — Azure Implementation

Azure port of the AWS pipeline in the repo root (`../lambdas`, `../glue_jobs`,
`../step_functions`, etc.). The AWS code is untouched — this is a parallel
implementation, phase 1 of a multi-cloud rollout (Azure now; AWS/GCP later).

See the root `README.md` for the pipeline's data flow and business logic —
this document only covers what's different about the Azure deployment.

## Service mapping

| AWS                             | Azure                                                        |
|----------------------------------|----------------------------------------------------------------|
| S3 (bronze/silver/gold/scripts)  | ADLS Gen2 (`modules/storage`)                                  |
| Lambda (3x)                      | Azure Functions, Python (`modules/functions`, `functions/`)    |
| Glue PySpark jobs                | Azure Databricks jobs (`modules/databricks`, `databricks_jobs/`) |
| Glue Data Catalog                | Databricks Unity Catalog                                        |
| Step Functions                   | Azure Data Factory pipeline (`modules/data-factory`, `data_factory/`) |
| EventBridge (rate(6 hours))      | ADF Schedule Trigger                                             |
| Athena                           | Databricks SQL Warehouse                                         |
| SNS                              | Azure Monitor Action Group (`modules/monitoring`)                |
| CloudWatch                       | Azure Monitor + Log Analytics                                    |
| IAM roles                        | Managed identities + Azure RBAC (`modules/security`)             |

## Repo layout

```
azure/
├── terraform/
│   ├── bootstrap/      # one-time: creates the tfstate storage account (run manually, local state)
│   ├── modules/        # reusable module source, one dir per infra layer
│   └── envs/dev/       # one root config per module — each has its OWN state file
├── functions/           # Azure Functions source (deployed by functions-deploy.yml, no Terraform)
├── databricks_jobs/      # PySpark job source (deployed by databricks-deploy.yml, no Terraform)
└── data_factory/
    └── pipeline_definition.json   # ADF pipeline activities — edit this to change orchestration logic
```

## Why a small change doesn't rebuild everything

1. **One Terraform state per module.** `envs/dev/<module>/backend.tf` gives
   `storage`, `security`, `monitoring`, `databricks`, `functions`, and
   `data-factory` each their own state file in the shared backend storage
   account. Terraform for one module physically cannot see or touch another
   module's resources.
2. **CI only plans/applies the module(s) that changed** (`dorny/paths-filter`
   in `terraform-plan.yml` / `terraform-apply.yml`), in dependency order
   (`storage → security/monitoring → databricks → functions → data-factory`).
   An unrelated module's job is skipped, not run as a no-op.
3. **Code changes never go through Terraform at all.** Editing a Function's
   `function_app.py` or a Databricks job's `.py` file triggers
   `functions-deploy.yml` / `databricks-deploy.yml` — these push code
   directly (`az functionapp` deploy / Databricks CLI `fs cp`) and never run
   `terraform apply`. This covers the majority of "chota change" cases.
4. Every `apply` is preceded by a `plan` posted on the PR — reviewers catch
   an accidental `-/+ (forces replacement)` before it merges.

## One-time setup

1. **Bootstrap the state backend** (local state, run once):
   ```bash
   cd terraform/bootstrap
   terraform init && terraform apply
   ```
   Save the resulting `storage_account_name` / `resource_group_name` as the
   `TFSTATE_STORAGE_ACCOUNT` / `TFSTATE_RESOURCE_GROUP` GitHub repo secrets.

2. **Unity Catalog metastore** — create/assign a Databricks Unity Catalog
   metastore for your region at the account level (one-time, outside
   Terraform — see `modules/databricks/variables.tf`). Save its ID as the
   `DATABRICKS_METASTORE_ID` secret.

3. **Azure AD app registration for GitHub Actions OIDC** (`azure/login`) with
   federated credentials for this repo, granted Contributor on the
   subscription/resource group. Save `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`,
   `AZURE_SUBSCRIPTION_ID` as secrets.

4. **Other required repo secrets**: `YOUTUBE_API_KEY`, `ALERT_EMAIL`,
   `DATABRICKS_HOST` (workspace URL, post-first-deploy),
   `FUNCTION_KEY_INGESTION` / `FUNCTION_KEY_JSON_TO_PARQUET` /
   `FUNCTION_KEY_DATA_QUALITY` (Function App host keys — only obtainable
   after the `functions` module's first apply; the `data-factory` module is
   deployed last for exactly this reason).

5. **First deploy**: merge to `main` with all `azure/terraform/**` paths
   touched (or run each module's apply manually in order) to bring up
   `storage → security → monitoring → databricks → functions`, fetch the
   Function host keys from the Azure Portal / `az functionapp keys list`,
   set the `FUNCTION_KEY_*` secrets, then merge again to deploy
   `data-factory`.

## Local Terraform commands

```bash
cd terraform/envs/dev/<module>
terraform init \
  -backend-config="resource_group_name=<TFSTATE_RESOURCE_GROUP>" \
  -backend-config="storage_account_name=<TFSTATE_STORAGE_ACCOUNT>" \
  -backend-config="container_name=tfstate"
terraform plan -var=... 
```
