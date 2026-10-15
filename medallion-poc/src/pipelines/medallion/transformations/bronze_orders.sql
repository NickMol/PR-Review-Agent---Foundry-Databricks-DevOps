-- Bronze: raw ingestion via Auto Loader.
-- Picks up new CSV files from the landing Volume on each pipeline run.
-- All columns stored as STRING with source names preserved.
CREATE OR REFRESH STREAMING TABLE ${catalog}.bronze.orders
  COMMENT "Raw order data — all columns as STRING, schema as sourced"
  TBLPROPERTIES ("quality" = "bronze")
AS
SELECT
  order_id,
  region,
  country,
  amount,
  quantity,
  order_date,
  current_timestamp()   AS _ingested_at,
  _metadata.file_path   AS _source_file
FROM STREAM read_files(
  '/Volumes/${catalog}/bronze/orders_landing',
  format       => 'csv',
  header       => 'true',
  inferSchema  => 'false',
  schema       => 'order_id STRING, region STRING, country STRING, amount STRING, quantity STRING, order_date STRING'
)
