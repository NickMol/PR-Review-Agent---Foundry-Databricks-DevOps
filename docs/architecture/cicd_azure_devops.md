# CI/CD Proposal — Azure DevOps + Databricks Asset Bundle

## Overview

Code is pushed to an Azure DevOps Git repository. An Azure Pipelines YAML pipeline picks it up, validates and deploys the Databricks Asset Bundle, and then triggers the Lakeflow pipeline. Promotion from dev → uat → prd happens via Pull Requests between protected branches, with manual approval gates before UAT and PRD deployments.

---

## Branching Strategy

```
feature/my-change  ──── PR ────► dev  ──── PR ────► uat  ──── PR ────► master
                                   │                   │                  │
                             auto-deploy           manual gate       manual gate
                                 dev                + deploy uat    + deploy prd
```

| Branch | Maps to DAB target | Deploy trigger | Approval required |
|---|---|---|---|
| `dev` | `dev` | push / merge | No |
| `uat` | `uat` | merge from `dev` | Yes — UAT approver |
| `master` | `prd` | merge from `uat` | Yes — PRD approver |
| `feature/*` | — | no deploy | — |

### Why this model

- One branch per environment maps cleanly to one DAB `--target`. No extra variable mapping needed.
- PRs are the promotion gate — code review happens on the way in, approval gates happen on the way out.
- Feature branches never deploy; they only exist until they are merged to `dev`.

---

## Promotion Flow

```
1. Developer creates feature/my-change from dev
2. Developer pushes and opens PR → dev
3. PR review + CI (validate only, no deploy)
4. Merge to dev
   → Pipeline deploys to dev catalog
   → Pipeline runs medallion_pipeline on dev
   → Developer validates results in dev

5. Developer opens PR: dev → uat
6. PR review + same CI check
7. Merge to uat
   → Pipeline waits for UAT Approver sign-off (Azure DevOps Environment gate)
   → Deploy to uat catalog
   → Pipeline runs medallion_pipeline on uat
   → UAT sign-off

8. Developer opens PR: uat → master
9. PR review (senior / release manager)
10. Merge to master
    → Pipeline waits for PRD Approver sign-off
    → Deploy to prd catalog
    → Pipeline runs medallion_pipeline on prd
```

---

## Azure DevOps Pipeline Structure

A single `azure-pipelines.yml` at the repository root with three stages, each gated by branch name. Stages run in isolation — pushing to `develop` only triggers the dev stage; merging to `main` only triggers the prd stage.

```
azure-pipelines.yml
├── Stage: Deploy_Dev    (condition: branch = develop)
├── Stage: Deploy_UAT    (condition: branch = uat, environment gate: uat-approvers)
└── Stage: Deploy_PRD    (condition: branch = main, environment gate: prd-approvers)
```

Each stage follows the same four steps:

```
1. Install Databricks CLI
2. databricks bundle validate --target <env>
3. databricks bundle deploy --target <env>          ← creates schemas/volumes if missing
4. databricks bundle run medallion_pipeline          ← triggers pipeline, waits for completion
         --target <env>
```

Step 4 is synchronous by default — the pipeline agent waits for the Databricks pipeline to finish. A failure in the Lakeflow pipeline fails the Azure DevOps stage and blocks promotion.

See `medallion-poc/azure-pipelines.yml` for the full YAML.

---

## Authentication

Since this PoC uses a single Databricks workspace, one set of credentials covers all environments. The catalog separation (dev/uat/prd) is handled entirely by the DAB target variable.

### Recommended: Service Principal with OAuth M2M

```
Azure AD
└── App Registration: svc-databricks-medallion-poc
    ├── Client ID   → stored in variable group (not secret)
    └── Client Secret → stored as secret in variable group

Databricks Workspace
└── svc-databricks-medallion-poc
    ├── Added as workspace user
    └── Granted CAN_MANAGE on pipelines, CREATE SCHEMA on dev/uat/prd catalogs
```

### Variable Group setup in Azure DevOps

Create one variable group `databricks-medallion` (Library → Variable groups):

| Variable | Value | Secret |
|---|---|---|
| `DATABRICKS_HOST` | `https://<workspace>.azuredatabricks.net` | No |
| `DATABRICKS_CLIENT_ID` | `<app-registration-client-id>` | No |
| `DATABRICKS_CLIENT_SECRET` | `<app-registration-secret>` | **Yes** |

Link this group to a pipeline or connect it to Azure Key Vault for secret rotation.

> For a quick PoC a PAT (Personal Access Token) works too — replace `DATABRICKS_CLIENT_ID` / `DATABRICKS_CLIENT_SECRET` with a single `DATABRICKS_TOKEN` variable.

---

## Azure DevOps Environments (Approval Gates)

Create two Environments in Azure Pipelines (Pipelines → Environments):

| Environment name | Purpose | Configure |
|---|---|---|
| `uat` | Gates the UAT stage | Add Approvals check → assign UAT approver group |
| `prd` | Gates the PRD stage | Add Approvals check → assign PRD approver group; optionally add Business Hours check |

The pipeline's deployment jobs reference these environments by name. Azure DevOps automatically pauses the run and sends an approval request before the stage executes.

---

## Branch Protection Policies (Azure DevOps)

Set these on Repos → Branches for `develop`, `uat`, and `main`:

| Policy | dev | uat | master |
|---|---|---|---|
| Require PR before merge | Yes | Yes | Yes |
| Minimum reviewers | 1 | 1 | 2 |
| Check for linked work items | Optional | Optional | Yes |
| Require CI build to pass | Yes (validate stage) | Yes | Yes |
| Delete source branch after merge | Yes | Yes | No |
| Require up-to-date branch | Yes | Yes | Yes |

---

## Repository Structure

The `medallion-poc/` folder is the DAB project root. The `azure-pipelines.yml` sits at the top level of the repository so Azure DevOps picks it up automatically.

```
(repo root)
├── azure-pipelines.yml               ← Azure DevOps pipeline definition
├── docs/
│   └── architecture/
│       ├── architecture.md
│       └── cicd_azure_devops.md      ← this document
└── medallion-poc/                    ← DAB project (all bundle commands run from here)
    ├── databricks.yml
    ├── resources/
    ├── src/
    └── data/
```

---

## Future Considerations

- **Per-environment service principals** — use a separate SP per catalog (dev-sp, uat-sp, prd-sp) to enforce least-privilege isolation. Requires one variable group per environment.
- **Run-as for production** — set `run_as` in `databricks.yml` under the `prd` target to ensure pipeline runs under the SP, not the deploying user.
- **Selective pipeline run** — if only Gold needs refreshing after a SQL change, use `databricks bundle run medallion_pipeline --target prd --refresh-selection gold.fact_orders_by_region` to avoid a full Bronze re-ingest.
- **Notifications** — add an Azure DevOps Service Hook or pipeline task to post to Teams/Slack on deployment failure in UAT or PRD.
