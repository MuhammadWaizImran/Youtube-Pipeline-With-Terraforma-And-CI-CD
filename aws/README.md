# YouTube Trending Data Pipeline — AWS Terraform + CI/CD

Terraform + GitHub Actions wrapper around the pipeline's existing AWS-native
code (`../lambdas`, `../glue_jobs`, `../data_quality`, `../step_functions`).
That application code is untouched — this replaces the root README's manual
`aws s3 mb` / `aws lambda create-function` / `aws stepfunctions
create-state-machine` steps with modular, incrementally-applied IaC, mirroring
the pattern already built for Azure (`../azure/README.md`).

## Repo layout

```
aws/
├── terraform/
│   ├── bootstrap/      # one-time: creates the tfstate S3 bucket + DynamoDB lock table (run manually, local state)
│   ├── modules/        # reusable module source, one dir per infra layer
│   └── envs/dev/       # one root config per module — each has its OWN state file
└── step_functions/
    └── pipeline_orchestration.tftpl   # Step Functions definition template — edit this to change orchestration logic
```

Existing root-level dirs are referenced directly by the Terraform modules
(no duplication):
- `lambdas/youtube_api_integstion`, `lambdas/json_to_parquet`, `data_quality/` → `lambda` module
- `glue_jobs/*.py` → `glue` module

## Module map (dependency order)

`storage → security/monitoring → glue → lambda → orchestration`

| Module | AWS resources |
|---|---|
| `storage` | 4 S3 buckets: bronze / silver / gold / scripts |
| `security` | 6 IAM roles (one per service, mirrors `../iam_permission/*.json`) |
| `monitoring` | SNS topic + email subscription, CloudWatch Log Group |
| `glue` | Glue Catalog databases (bronze/silver/gold), 2 Glue jobs, Athena workgroup |
| `lambda` | 3 Lambda functions (ingestion, json_to_parquet, data_quality) |
| `orchestration` | Step Functions state machine + EventBridge schedule rule |

## Why a small change doesn't rebuild everything

1. **One Terraform state per module** — each of the 6 modules above has its
   own state file (`envs/dev/<module>/backend.tf`, keyed
   `dev/<module>.tfstate` in the shared bootstrap S3 bucket). Changing
   `orchestration` cannot touch `storage`/`lambda`/`glue` state.
2. **The EventBridge schedule is isolated in `orchestration`.** Changing
   `schedule_expression` (or the state machine's control flow in
   `pipeline_orchestration.tftpl`) only ever runs `terraform apply` against
   the `orchestration` module — storage, IAM, Glue jobs, and Lambda functions
   are untouched. This is the concrete answer to "if I change the EventBridge
   schedule, the whole infrastructure should not redeploy."
3. **CI only plans/applies the module(s) that changed**
   (`dorny/paths-filter` in `aws-terraform-plan.yml` / `aws-terraform-apply.yml`),
   in the dependency order above. An unrelated module's job is skipped
   entirely, not run as a no-op.
4. **Code-only changes never touch Terraform.** Editing a Lambda's
   `lambda_function.py` (or `dq_lambda.py`) triggers `aws-lambda-deploy.yml`,
   which runs `aws lambda update-function-code` directly. Editing a Glue
   PySpark script triggers `aws-glue-deploy.yml`, which runs `aws s3 cp` to
   the scripts bucket — the `glue` module's Terraform state has
   `lifecycle.ignore_changes` on that object's content specifically so this
   never causes a diff. Neither workflow calls `terraform apply`.
5. Every `apply` is preceded by a `plan` posted on the PR for review before
   merge.

## One-time setup

1. **Bootstrap the state backend** (local state, run once):
   ```bash
   cd terraform/bootstrap
   terraform init && terraform apply
   ```
   Save the resulting `bucket_name` / `dynamodb_table_name` as the
   `TFSTATE_BUCKET` / `TFSTATE_DYNAMODB_TABLE` GitHub repo secrets.

2. **GitHub Actions OIDC role** — create an IAM role trusted by
   `token.actions.githubusercontent.com` for this repo (via
   `aws-actions/configure-aws-credentials`), with permissions to manage the
   S3/IAM/Glue/Lambda/SFN/EventBridge/SNS/CloudWatch resources above. Save
   its ARN as `AWS_ROLE_ARN`.

3. **Other required repo secrets**: `YOUTUBE_API_KEY`, `ALERT_EMAIL`,
   `SCRIPTS_BUCKET_NAME` (from the `storage` module's output, used by
   `aws-glue-deploy.yml`).

4. **First deploy**: merge to `main` with all `aws/terraform/**` paths
   touched (or apply each module manually, in order) to bring up
   `storage → security → monitoring → glue → lambda → orchestration`.

5. The EventBridge schedule rule is created **disabled**
   (`schedule_enabled = false`) so nothing runs automatically until you've
   verified the pipeline manually. Flip it to `true` in
   `envs/dev/orchestration` (a small, `orchestration`-only change) once ready.

## Local Terraform commands

```bash
cd terraform/envs/dev/<module>
terraform init \
  -backend-config="bucket=<TFSTATE_BUCKET>" \
  -backend-config="dynamodb_table=<TFSTATE_DYNAMODB_TABLE>" \
  -backend-config="region=us-east-1"
terraform plan -var=...
```

## Deploying manually (this project is being run without CI on the AWS side
for now — same commands the workflows run)

```bash
# 1. storage
cd terraform/envs/dev/storage && terraform init -backend-config=... && terraform apply

# 2. security / monitoring (either order)
cd ../security && terraform init -backend-config=... && \
  terraform apply -var=tfstate_bucket=... -var=tfstate_dynamodb_table=... -var=youtube_api_key=...
cd ../monitoring && terraform init -backend-config=... && \
  terraform apply -var=tfstate_bucket=... -var=tfstate_dynamodb_table=... -var=alert_email=...

# 3. glue
cd ../glue && terraform init -backend-config=... && terraform apply -var=tfstate_bucket=... -var=tfstate_dynamodb_table=...

# 4. lambda
cd ../lambda && terraform init -backend-config=... && \
  terraform apply -var=tfstate_bucket=... -var=tfstate_dynamodb_table=... -var=youtube_api_key=...

# 5. orchestration
cd ../orchestration && terraform init -backend-config=... && terraform apply -var=tfstate_bucket=... -var=tfstate_dynamodb_table=...
```
