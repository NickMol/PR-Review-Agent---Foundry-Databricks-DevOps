# Architecture — AI PR Review Agent

## Overview

When a PR is opened or updated in Azure DevOps, a pipeline automatically sends the PR context to an Azure AI Foundry agent. The agent retrieves the changed files via its MCP connection to ADO, reviews them against the platform rules document, and posts findings as comments on the PR.

---

## Architecture Diagram

```
Azure DevOps
│
│  PR opened / updated
│       │
│       ▼
│  azure-pipelines-pr-review.yml  (PR pipeline trigger)
│       │
│       │  azure-ai-projects SDK
│       │  DefaultAzureCredential (service connection)
│       ▼
│  Azure AI Foundry
│  Agent: pr-review-agent
│       │
│       ├── MCP tool ──────────────► Azure DevOps REST API
│       │   (read PR diff,               (get changed files,
│       │    file contents)               file contents)
│       │
│       ├── File search ───────────► platform-rules.docx
│       │   (look up rules              (uploaded to Foundry
│       │    for file types)             file store)
│       │
│       └── POST comments ─────────► Azure DevOps REST API
│                                        (post review threads on PR)
```

---

## How It Works

1. A developer opens or updates a PR targeting `dev`, `uat`, or `master`
2. The ADO pipeline triggers and runs `azure-pipelines-pr-review.yml`
3. The pipeline authenticates to Azure AI Foundry using the `azure-devops-serviceconnection` service connection
4. It sends the agent a prompt containing the PR number, repo, project, and org URL
5. The agent uses its MCP tools to fetch the PR diff and changed file contents
6. The agent searches the platform rules document for rules relevant to the changed file types
7. The agent posts its findings as comments on the PR and returns a summary response
8. The pipeline prints the agent's response and confirms whether comments were posted

---

## Components

### ADO Pipeline (`azure-pipelines-pr-review.yml`)

Triggers on PR creation/update. Installs the `azure-ai-projects` SDK, authenticates via the service connection, and calls the Foundry agent using `AIProjectClient`.

Key variables (from variable group `ai-foundry-config`):
- `AI_FOUNDRY_ENDPOINT` — full project endpoint, e.g. `https://foundry-poc-nm.services.ai.azure.com/api/projects/devops-process`
- `AGENT_NAME` — name of the agent in Foundry, e.g. `pr-review-agent`

### Azure DevOps Service Connection

Name: `azure-devops-serviceconnection`

An Azure Resource Manager service connection using workload identity federation. Its service principal is granted **Foundry User** role on the Azure AI Foundry resource. This allows `DefaultAzureCredential` in the pipeline to obtain a token scoped to `https://cognitiveservices.azure.com/.default`.

### Azure AI Foundry Agent (`pr-review-agent`)

Configured with:
- **System prompt** — instructions on how to review code, what to flag, and how to format comments
- **File search tool** — searches `platform-rules.docx` for rules relevant to the changed file types
- **MCP tool** — connected to the Azure DevOps repo; exposes tools to read PR diffs and file contents
- **Model** — GPT-4o or equivalent

### Platform Rules Document

A Word document uploaded to the Foundry project's file store. Contains rules per file type (SQL, YAML, Python). The agent retrieves relevant sections at review time. Update the document without touching any code.

---

## Role Assignments

| Who | Role | On | Why |
|---|---|---|---|
| Your account | Azure AI Developer | Foundry resource (IAM) | Create/manage agents in Foundry portal |
| Service connection SP | **Foundry User** | Foundry resource (IAM) | Pipeline can call the agent API |
| Service connection SP | ADO Contribute to pull requests | ADO repo permissions | Agent can post PR comments |

---

## Key Design Decisions

| Decision | Choice | Reason |
|---|---|---|
| Trigger | ADO PR pipeline | No extra infrastructure; runs natively on PR events |
| Auth | Service connection + DefaultAzureCredential | No secrets; workload identity federation |
| Agent interaction | `get_openai_client()` → `conversations` + `responses` API | Required by azure-ai-projects SDK 2.x |
| Rules storage | Foundry file store (Word doc) | Update rules without code changes |
