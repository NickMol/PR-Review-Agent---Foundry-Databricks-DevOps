# Repository containing the code for a PR review agent. It includes the folders: 
- agent: folder with the yml agent containing the instructions and tools
- medallion-poc:Contains the Databricks Declarative Automation Bundle with the medallion architecture, as well as the yml pipelines for deployment to dev, uat, prd and the AI pipeline review
- Docs: info about the project architecture etc.

Below more info on the step by step setup:

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
6. **Tools** → **+ MCP** → Add the Azure DevOps MCP server as a tool. I needs to have a Project Managed Identity. This managed identity needs access in ADO to review the PRs. 
<img width="744" height="127" alt="image" src="https://github.com/user-attachments/assets/ce4de8f2-09f9-4788-9421-6f046849235e" />

7. **Save**

<img width="871" height="1000" alt="image" src="https://github.com/user-attachments/assets/430a56f6-45ec-457f-aab2-445009d85426" />


### 2.6 Grant the Project Managed Identity access in Azure DevOps

The ADO MCP tool authenticates using the **Project Managed Identity** of your Foundry project. This identity must be added as a user in Azure DevOps and granted permission to post PR comments.

**Finding the identity**

The identity name follows this pattern:

```
<foundry-name>/projects/<project-name>
```

Example: `foundry-poc-nm/projects/devops-process`

If you're unsure of the exact name, look it up via the Object ID:

1. Foundry portal → your project → **Resource Management** → **Identity**
<img width="744" height="359" alt="image" src="https://github.com/user-attachments/assets/900473ea-bcd6-4d4b-98ff-a6427abbe13e" />
2. Copy the **Object ID**
3. Paste it into the Azure Portal top search bar — it will resolve to the service principal name in Entra ID
<img width="744" height="189" alt="image" src="https://github.com/user-attachments/assets/efde79ff-cb3e-4993-8639-5638cb2e315e" />

**Adding the identity to Azure DevOps**

1. ADO → **Organization settings** → **Users** → **Add users**
2. Search for the identity name (e.g. `foundry-poc-nm/projects/devops-process`) and add it to the organization
3. In your ADO project → **Project settings** → **Permissions** → add the identity with access to the project
<img width="744" height="202" alt="image" src="https://github.com/user-attachments/assets/c89835c4-72b7-433d-8204-464e412566c5" />

**Setting repository permissions**

1. ADO → your project → **Project settings** → **Repositories** → select your repo → **Security**
2. Search for the identity
3. Set **Contribute to pull requests** → **Allow**
4. Set **Delete repository** → **Deny**
5. Consider adding further guardrails (e.g. deny force push, deny manage permissions) depending on your security requirements

<img width="744" height="307" alt="image" src="https://github.com/user-attachments/assets/fc78b50d-f541-48c1-ae6f-e4b8c71ce1b3" />


**Verification tip**

Open the agent playground in the Foundry portal and ask: *"Can you list the repos in Azure DevOps using your tool?"* — if it responds with repo names, the identity and permissions are set up correctly.
<img width="1488" height="842" alt="image" src="https://github.com/user-attachments/assets/4c1f7828-0036-440c-a83d-5b0bafd8019d" />

### 2.7 Note the Foundry endpoint

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
| `AI_FOUNDRY_ENDPOINT` | the project endpoint from step 2.7 
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
4. **Save** — name it e.g. `PR-Review-Pipeline`
5. When prompted, allow the pipeline to access the `ai-foundry-config` variable group

> The YAML file has no trigger defined. The pipeline is triggered via a **build validation policy** in Azure DevOps, not by a push event — see step 3.4.1 below.

#### 3.4.1 Configure the build validation trigger

The PR review pipeline must run automatically whenever a PR is opened. This is done via a branch policy rather than a YAML trigger.

1. ADO → **Project settings** → **Repositories** → select your repository → **Policies**
2. Scroll down to the branch you want the review to run on (e.g. `dev`) and click it
3. Under **Build validation** → **+** → select the `PR-Review-Pipeline` you just created
4. Set **Trigger** to **Automatic** and **Policy requirement** to **Required** (or Optional for a softer rollout)
5. Save
6. Repeat for any other branches that require the review (e.g. `uat`, `master`)

<img width="744" height="278" alt="image" src="https://github.com/user-attachments/assets/03e6161e-88f7-49aa-a770-b69124e40929" />


With this in place, every time a PR is opened or updated targeting that branch, ADO will automatically run the pipeline. The pipeline then prompts the AI agent with the PR number, repository, and project — all parameterised so it works across repos without code changes.

### 3.5 Create the service connection

This allows the PR review pipeline to authenticate to Azure AI Foundry so it can let the agent know to review a PR.

1. **Project settings** (bottom-left) → **Service connections** → **New service connection**
2. Type: **Azure Resource Manager** → **Workload identity federation (automatic)**
3. Scope: select the subscription and resource group containing the Foundry resource
4. Name: `azure-devops-serviceconnection`
5. Save

> Creating this service connection automatically creates an **App Registration** in Azure Entra ID on your behalf.

### 3.6 Grant the service connection Foundry User role

The App Registration created in step 3.5 needs the **Foundry User** role on the Azure AI Foundry resource so the pipeline can call the agent.

**Find the App Registration name**

1. ADO → **Project settings** → **Service connections** → open `azure-devops-serviceconnection`
2. Click **Manage App Registration** — this opens the App Registration in the Azure Portal
3. Copy the **Display name** of the App Registration

**Assign the role**

1. Azure Portal → your **Foundry resource** (the hub/workspace, not the project)
2. **Access control (IAM)** → **Add role assignment**
3. Role: **Foundry User**
4. Members: search for the App Registration name you copied above and select it
5. Save and wait ~2 minutes for the role to propagate

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
