-- Gold: regional sales fact — Materialized View over Silver.
--
-- Silver is a Streaming Table, so Gold must use a batch read (no STREAM).
-- A Materialized View recomputes the aggregation whenever Silver changes.
-- With serverless + row tracking enabled on Silver, refresh is incremental;
-- otherwise it falls back to a full recompute (acceptable for this PoC).
CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.gold.fact_orders_by_region
  COMMENT "Regional sales aggregation — suitable for BI/reporting"
  TBLPROPERTIES ("quality" = "gold")
AS
SELECT
  Region,
  Country,
  SUM(Amount)   AS TotalAmount,
  SUM(Quantity) AS TotalQuantity,
  COUNT(*)      AS OrderCount
FROM ${catalog}.silver.orders
GROUP BY Region, Country
