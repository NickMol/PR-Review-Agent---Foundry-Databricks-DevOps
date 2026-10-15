# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Databricks Proof of Concept project (Accenture). It is in early-stage setup — no implementation exists yet.

## Repository Structure

```
docs/
  architecture/       # Architecture documentation (to be created)
  requirements/
    1. Create architecture.md   # Initial requirement: define the architecture
```

## Development Context

This project targets the Databricks platform. Use the Databricks-specific skills available in Claude Code (e.g., `/databricks:databricks-core`, `/databricks:databricks-dabs`, `/databricks:databricks-pipelines`) when implementing features.

## Bundle Commands

All commands run from `medallion-poc/`.

```bash
# Validate
databricks bundle validate --target dev --profile <profile>

# Deploy (creates schemas, volumes, pipeline)
databricks bundle deploy --target dev --profile <profile>

# Run pipeline
databricks bundle run medallion_pipeline --target dev --profile <profile>

# Upload sample data to trigger ingestion
databricks fs cp data/sample_orders.csv dbfs:/Volumes/dev/bronze/orders_landing/ --profile <profile>
```

Targets: `dev` (default), `uat`, `prd` — each maps to its own UC catalog.

## Architecture

See `docs/architecture/architecture.md` for full design. Summary:

- **Bronze** — Streaming Table via Auto Loader. All strings, source column names.
- **Silver** — Streaming Table via Auto CDC (SCD Type 1 upsert on `OrderId`). Typed + CamelCase.
- **Gold** — Materialized View (batch read over Silver). Regional sales fact aggregation.
- **Pipeline config param** `${catalog}` is used inside SQL files to reference the active catalog, injected via `configuration:` in the pipeline resource YAML.
