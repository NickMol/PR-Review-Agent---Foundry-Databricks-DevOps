-- Silver: typed columns, CamelCase names, upsert keyed on OrderId.
--
-- Pattern: temp view applies the transform on the stream, then AUTO CDC
-- performs the SCD Type 1 upsert into the persistent Streaming Table.
-- This is the LDP-native way to merge/dedup from a streaming source.

CREATE TEMPORARY VIEW silver_orders_staged AS
SELECT
  CAST(order_id   AS INT)            AS OrderId,
  region                              AS Region,
  country                             AS Country,
  CAST(amount     AS DECIMAL(10, 2)) AS Amount,
  CAST(quantity   AS INT)            AS Quantity,
  CAST(order_date AS DATE)           AS OrderDate,
  YEAR(CAST(order_date AS DATE))     AS OrderYear,
  _ingested_at                        AS IngestedAt
FROM STREAM(${catalog}.bronze.orders);

CREATE OR REFRESH STREAMING TABLE ${catalog}.silver.orders
  COMMENT "Conformed orders — typed columns, CamelCase, deduped by OrderId"
  TBLPROPERTIES ("quality" = "silver");

CREATE FLOW silver_orders_cdc
AS AUTO CDC INTO ${catalog}.silver.orders
FROM STREAM(silver_orders_staged)
KEYS (OrderId)
IGNORE NULL UPDATES
SEQUENCE BY IngestedAt
STORED AS SCD TYPE 1;
