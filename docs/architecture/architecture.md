# Databricks Medallion Architecture – PoC

## Overview

This PoC implements a medallion architecture (Bronze → Silver → Gold) on Databricks using:

- **Lakeflow Declarative Pipelines (LDP)** — formerly Delta Live Tables. The single pipeline covers all three layers.
- **Databricks Asset Bundle (DAB)** — for deployment, multi-environment promotion, and CI/CD integration with Azure DevOps.
- **Unity Catalog** — for catalog, schema, volume, and table governance.

---

## Design Decisions & Recommendations

### Lakeflow Declarative Pipelines (LDP) over standard Jobs

LDP is the recommended approach because it handles the full medallion pattern natively:

| Requirement | LDP capability |
|---|---|
| Auto-detect new files | Auto Loader built-in via `STREAM read_files(...)` |
| Upsert / dedup in Silver | Auto CDC (`AUTO CDC INTO ... FROM STREAM`) — SCD Type 1 |
| Gold aggregation | Materialized View with batch read over Silver |
| Data quality | Expectations / constraints declarative |
| Incremental refresh | Automatic — no manual watermarking needed |

### Auto Loader → Bronze (Streaming Table)

Auto Loader monitors a Unity Catalog Volume for new CSV files and appends them to Bronze. It tracks processed files automatically — re-running the pipeline only picks up files added since the last run. Bronze stores data **as-is** (all strings) plus two metadata columns: `_ingested_at` and `_source_file`.

### Auto CDC → Silver (Streaming Table, SCD Type 1 upsert)

Silver uses LDP's `AUTO CDC INTO` pattern to read from Bronze (streaming) and perform an upsert keyed on `order_id`. This is the native LDP way to do deduplication and updates — it is more correct than a manual `MERGE INTO` in a standard Job because it handles out-of-order events and exactly-once semantics. The transform casts all columns to their proper types and renames them to CamelCase.

### Materialized View → Gold

Gold is a Materialized View reading Silver as a **batch** (no `STREAM`). Per Databricks best practice, aggregations over a streaming source must use a Materialized View with a batch read — Streaming Tables are append-only and cannot recompute aggregates. The Gold table acts as a regional sales fact table suitable for BI consumption.

### One pipeline, three schemas, parameterised catalog

A single LDP pipeline writes to three schemas (`bronze`, `silver`, `gold`) using fully-qualified names (`${catalog}.bronze.orders` etc.). The catalog is a DAB variable so the same pipeline deploys to `dev`, `uat`, or `prd` by selecting the bundle target.

```
dev  catalog  →  dev.bronze   /  dev.silver   /  dev.gold
uat  catalog  →  uat.bronze   /  uat.silver   /  uat.gold
prd  catalog  →  prd.bronze   /  prd.silver   /  prd.gold
```

Schemas and the landing Volume are declared as DAB resources, so they are created on `bundle deploy` if they do not already exist.

---

## Data Flow

```
Azure Blob / ADLS
       │  (CSV files dropped)
       ▼
┌─────────────────────────┐
│  UC Volume              │
│  {catalog}.bronze       │
│  /orders_landing/       │
└─────────┬───────────────┘
          │  Auto Loader (STREAM read_files)
          ▼
┌─────────────────────────┐
│  BRONZE                 │  Streaming Table
│  {catalog}.bronze       │  All strings, source column names
│  .orders                │  + _ingested_at, _source_file
└─────────┬───────────────┘
          │  Auto CDC (SCD Type 1 upsert on order_id)
          ▼
┌─────────────────────────┐
│  SILVER                 │  Streaming Table
│  {catalog}.silver       │  Typed columns, CamelCase names
│  .orders                │  Deduped & upserted by OrderId
└─────────┬───────────────┘
          │  Batch read (Materialized View)
          ▼
┌─────────────────────────┐
│  GOLD                   │  Materialized View
│  {catalog}.gold         │  Aggregated regional sales fact
│  .fact_orders_by_region │
└─────────────────────────┘
```

---

## Unity Catalog Structure

```
{catalog}                   ← dev | uat | prd
├── bronze                  ← schema (created by DAB on deploy)
│   ├── Volume: orders_landing   ← drop CSV files here
│   └── Table: orders       ← Streaming Table (all strings)
├── silver                  ← schema (created by DAB on deploy)
│   └── Table: orders       ← Streaming Table (typed, CamelCase)
└── gold                    ← schema (created by DAB on deploy)
    └── View: fact_orders_by_region  ← Materialized View
```

---

## Table Definitions

### Bronze: `{catalog}.bronze.orders`

All columns stored as `STRING`. Source column names preserved.

| Column | Type | Notes |
|---|---|---|
| order_id | STRING | Source key |
| region | STRING | |
| country | STRING | |
| amount | STRING | Raw numeric string |
| quantity | STRING | Raw integer string |
| order_date | STRING | Raw date string |
| _ingested_at | TIMESTAMP | Added by pipeline at ingest |
| _source_file | STRING | Source file path from `_metadata.file_path` |

### Silver: `{catalog}.silver.orders`

Typed columns, CamelCase names, deduped by `OrderId`.

| Column | Type | Notes |
|---|---|---|
| OrderId | INT | Primary key for CDC upsert |
| Region | STRING | |
| Country | STRING | |
| Amount | DECIMAL(10,2) | |
| Quantity | INT | |
| OrderDate | DATE | |
| IngestedAt | TIMESTAMP | Carried from Bronze |

### Gold: `{catalog}.gold.fact_orders_by_region`

Materialized View — regional sales aggregation.

| Column | Type | Notes |
|---|---|---|
| Region | STRING | |
| Country | STRING | |
| TotalAmount | DECIMAL(18,2) | SUM(Amount) |
| TotalQuantity | BIGINT | SUM(Quantity) |
| OrderCount | BIGINT | COUNT(*) |

---

## Sample CSV Data

File: `data/sample_orders.csv`

```
order_id,region,country,amount,quantity,order_date
1001,EMEA,Netherlands,1250.00,5,2024-10-01
1002,EMEA,Germany,875.50,3,2024-10-02
1003,NA,United States,3200.00,12,2024-10-02
1004,APAC,Australia,640.75,2,2024-10-03
1005,NA,Canada,980.00,4,2024-10-04
1006,EMEA,Belgium,420.00,1,2024-10-05
1007,APAC,Japan,2100.00,8,2024-10-06
1008,EMEA,Netherlands,560.00,2,2024-10-07
```

Upload this file to the Volume at `{catalog}.bronze.orders_landing` to trigger the pipeline.

---

## DAB Project Structure

```
medallion-poc/
├── databricks.yml                          ← Bundle root: variables, targets (dev/uat/prd)
├── resources/
│   ├── schemas.yml                         ← UC schemas: bronze, silver, gold (created on deploy)
│   ├── volumes.yml                         ← UC Volume: bronze.orders_landing
│   └── medallion_pipeline.pipeline.yml     ← LDP pipeline config
├── src/
│   ├── bronze_orders.sql                   ← Streaming Table via Auto Loader
│   ├── silver_orders.sql                   ← Auto CDC upsert from Bronze
│   └── gold_fact_orders_by_region.sql      ← Materialized View aggregation
└── data/
    └── sample_orders.csv                   ← Dummy data for testing
```

### `databricks.yml` — Multi-environment targets

```yaml
bundle:
  name: medallion-poc

variables:
  catalog:
    description: Unity Catalog catalog name (maps to environment)
    default: dev

targets:
  dev:
    default: true
    variables:
      catalog: dev
  uat:
    variables:
      catalog: uat
  prd:
    variables:
      catalog: prd
```

---

## Azure DevOps Integration (Future)

The DAB is designed to be triggered from an Azure DevOps pipeline. The pipeline would:

1. Check out the repo
2. Run `databricks bundle validate --target <env>`
3. Run `databricks bundle deploy --target <env>`
4. Run `databricks bundle run medallion_pipeline --target <env>`

Authentication from Azure DevOps uses a Databricks Service Principal with a PAT or OAuth M2M token stored as a pipeline secret. The Databricks CLI profile is configured via environment variable (`DATABRICKS_HOST`, `DATABRICKS_TOKEN`).

---

## Key Constraints & Caveats

- **Incremental MV refresh** (Gold) requires Databricks serverless compute + `delta.enableRowTracking = true` on Silver. Without both, Gold falls back to a full recompute on each pipeline run. For this PoC on non-serverless, full recompute is acceptable.
- **Full pipeline refresh** re-processes Bronze from scratch and destroys streaming state — only use when data must be reloaded from source files. Normal pipeline runs are always incremental.
- **Volume path** for Auto Loader: `dbfs:/Volumes/{catalog}/bronze/orders_landing/` — the `dbfs:` prefix is required in CLI commands even for UC Volume paths.
- **Schema creation** is handled by the DAB `resources/schemas.yml` declaration. `bundle deploy` creates schemas that do not yet exist; it does not drop or alter existing ones.
