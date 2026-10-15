# Project Setup Guide

This guide covers the full setup of the project across three areas:

1. [Azure Databricks](#1-azure-databricks) — workspace, Unity Catalog, catalogs
2. [Azure AI Foundry — PR Review Agent](#2-azure-ai-foundry--pr-review-agent) — agent, model, platform rules
3. [Azure DevOps](#3-azure-devops) — repo, pipelines, branch policies, variable groups

Complete them in order. Each section builds on the previous.

---

## 1. Azure Databricks

### 1.1 Create the workspace

1. Azure Portal → search **Azure Databricks** → **Create**
2. Fill in:
   - Resource group: `rg-databricks-poc`
   - Workspace name: e.g. `databricks-poc`
   - Region: West Europe (or close to you)
   - Pricing tier: **Premium** (required for Unity Catalog)
3. Review + create → wait ~2 min
4. Note the workspace URL: `https://adb-xxxx.azuredatabricks.net`

### 1.2 Enable Unity Catalog

1. In the workspace → left sidebar → **Catalog** icon
2. If catalogs are already listed (e.g. `main`), Unity Catalog is active — skip to 1.3
3. Otherwise: go to `accounts.azuredatabricks.net` → your workspace → **Enable Unity Catalog** → assign or create a metastore

### 1.3 Create the three catalogs

The bundle creates schemas and volumes automatically, but catalogs must exist first.

1. Workspace → **Catalog** → **Create catalog**
2. Create three catalogs: `dev`, `uat`, `prd`
3. Leave storage as default (metastore root)

### 1.4 Generate a PAT token

1. Workspace → top-right profile icon → **Settings** → **Developer** → **Access tokens**
2. **Generate new token** — comment: `azure-devops-poc`, lifetime: 90 days
3. Copy the token immediately — you will not see it again, you will need it in step 3.2

---

## 2. Azure AI Foundry — PR Review Agent

### 2.1 Create the Foundry project

1. Azure Portal → search **Azure AI Foundry** → **Create**
   - Resource group: `rg-databricks-poc` or new `rg-ai-agents`
   - Name: e.g. `foundry-poc-nm`
   - Region: whatever is closest, I used west europe
2. After deploy → **Go to resource** → **Launch Azure AI Foundry portal**

### 2.2 Assign yourself access

Creating the resource does not automatically give you access to creating agents inside the Foundry portal.

- Azure Portal → Foundry resource → **Access control (IAM)**
- **Add role assignment** → **Foundry Owner** → assign to your account


### 2.5 Create the agent

1. Foundry portal → **Agents** → **+ New agent**
2. Name: `pr-review-agent`
3. Model: select the default GPT-5 deployment or pick whatever you think is best
4. **Instructions** — Available in the `agent/pr-review-agent.yml`
5. **Tools** → **+ File search** → Upload the platform guiding principles document. Available at `agent/Data Engineering Platform Guiding Principles.docx`
6. **Tools** → **+ MCP** → Add the Azure DevOps MCP server as a tool. I needs to have a Platform Managed Identity. 
7. **Save**

### 2.6 Note the Foundry endpoint

1. Foundry portal → your project → **Overview**
2. Copy the **Project endpoint** — format: `https://<hub>.services.ai.azure.com/api/projects/<project>`
3. You will need this in step 3.2 when configuring the ADO variable group

---

## 3. Azure DevOps

### 3.1 Create the repository and push code

1. ADO → your project → **Repos** → **New repository**
   - Name: `medallion-poc`
   - No README, no .gitignore
2. From your local project folder, run:

```bash
git init
git add .
git commit -m "Initial commit"
git remote add origin <url-from-azure-devops>
git push -u origin master
```

3. Create the other long-lived branches:

```bash
git checkout -b dev && git push -u origin dev
git checkout -b uat && git push -u origin uat
```

4. ADO → **Repos** → **Branches** → three-dot menu next to `dev` → **Set as default**

### 3.2 Create variable groups

Go to **Pipelines** → **Library** → **+ Variable group**.

**Group 1: `databricks-medallion`**

| Variable | Value | Secret |
|---|---|---|
| `DATABRICKS_HOST` | `https://<workspace>.azuredatabricks.net` 
| `DATABRICKS_TOKEN` | the PAT from step 1.4 

**Group 2: `ai-foundry-config`**

| Variable | Value | Secret |
|---|---|---|
| `AI_FOUNDRY_ENDPOINT` | the project endpoint from step 2.6 
| `AI_FOUNDRY_AGENT_NAME` | `pr-review-agent` in my case

### 3.3 Register the Databricks deploy pipeline

This pipeline validates and deploys the Databricks Asset Bundle on every push to `dev`, `uat`, or `master`.

1. **Pipelines** → **New pipeline**
2. **Azure Repos Git** → select `medallion-poc`
3. **Existing Azure Pipelines YAML file**
   - Branch: `master`
   - Path: `/medallion-poc/azure-pipelines.yml`
4. **Save** (do not run yet)
5. When prompted, allow the pipeline to access the `databricks-medallion` variable group

### 3.4 Register the PR review pipeline

This pipeline calls the Azure AI Foundry agent to review PRs automatically.

1. **Pipelines** → **New pipeline**
2. **Azure Repos Git** → select `medallion-poc`
3. **Existing Azure Pipelines YAML file**
   - Branch: `master`
   - Path: `/medallion-poc/azure-pipelines-pr-review.yml`
4. **Save**
5. When prompted, allow the pipeline to access the `ai-foundry-config` variable group

### 3.5 Create the service connection

This allows the PR review pipeline to authenticate to Azure AI Foundry.

1. **Project settings** (bottom-left) → **Service connections** → **New service connection**
2. Type: **Azure Resource Manager** → **Workload identity federation (automatic)**
3. Scope: select the subscription and resource group containing the Foundry resource
4. Name: `azure-devops-serviceconnection`
5. Save

### 3.6 Grant the service connection Foundry User role

The PR review pipeline authenticates using the service connection. Its service principal needs permission to call the agent.

1. Azure Portal → Foundry resource → **Access control (IAM)**
2. **Add role assignment** → **Foundry User**
3. Assign to the service principal created by `azure-devops-serviceconnection`
   - Find it by searching the service connection name or looking up its object ID in Entra ID
4. Save and wait ~2 minutes for the role to propagate

> Without this role the pipeline gets a 403 when trying to call the agent.

### 3.7 Create environments with approval gates

These pause the deploy pipeline before UAT and PRD deployments until a human approves.

1. **Pipelines** → **Environments** → **New environment**
   - Name: `uat`, Resource: None → Create
2. Open `uat` → three-dot menu → **Approvals and checks** → **+** → **Approvals**
   - Add yourself or a group as approver → Create
3. Repeat for `prd`

### 3.8 Set branch protection policies

Do this for `dev`, `uat`, and `master`: **Repos** → **Branches** → three-dot menu → **Branch policies**.

| Policy | dev | uat | master |
|---|---|---|---|
| Require minimum reviewers | 1 | 1 | 1 |
| Build validation | Add — select deploy pipeline | Add | Add |
| Require up-to-date branch | Yes | Yes | Yes |

> With a single-person PoC you can approve your own PRs, but having the policy in place proves the pattern.

---

## Verification — end-to-end test

### Databricks pipeline

1. Create a feature branch, make a small change, push and open a PR → `dev`
2. Merge the PR → **Pipelines** → watch the deploy pipeline trigger automatically
3. After a successful deploy, upload sample data:

```bash
databricks fs cp data/sample_orders.csv \
  dbfs:/Volumes/dev/bronze/orders_landing/sample_orders.csv \
  --profile <your-profile>
```

4. Trigger another pipeline run to process the file through Bronze → Silver → Gold

### PR review agent

1. Open any PR targeting `dev`, `uat`, or `master` with files under `medallion-poc/`
2. The PR review pipeline triggers automatically
3. Pipeline logs will confirm: `✓ Agent posted review on the PR.`
4. Check the PR in ADO — the agent should have posted a structured comment with a findings table

---

## What lives where

| Component | Location |
|---|---|
| Databricks workspace | Azure Portal → `rg-databricks-poc` |
| Unity Catalog catalogs | Databricks workspace → Catalog explorer |
| Databricks PAT | Databricks → Settings → Access tokens |
| Foundry resource + agent | Azure Portal → `rg-ai-agents` → Foundry portal |
| Platform rules document | Foundry portal → Files |
| ADO variable groups | ADO → Pipelines → Library |
| Deploy pipeline | ADO → Pipelines → (points at `medallion-poc/azure-pipelines.yml`) |
| PR review pipeline | ADO → Pipelines → (points at `medallion-poc/azure-pipelines-pr-review.yml`) |
| Service connection | ADO → Project settings → Service connections |
| Approval gates | ADO → Pipelines → Environments → `uat` / `prd` |
| Branch policies | ADO → Repos → Branches → each branch |
