/*
  Getting Started with Task Graphs
  02_build_task_graph.sql - Act 1: build the member tasks and the task graph,
  commit it, run it once and inspect the run.
*/

USE ROLE DEMO_TASK_GRAPHS_ROLE;
USE SCHEMA DEMO_TASK_GRAPHS.PIPELINE;
USE WAREHOUSE DEMO_TASK_GRAPHS_WH;

-- ------------------------------------------------------------
-- Member tasks. No WAREHOUSE and no SCHEDULE: compute comes from the
-- graph's TASK_DEFAULTS and the schedule lives on the graph.
-- ------------------------------------------------------------

-- Root: load a fresh batch of 100 synthetic orders. When the run's CONFIG
-- sets inject_bad_rows to true, three orders get a negative amount.
CREATE OR REPLACE TASK DEMO_TASK_GRAPHS.PIPELINE.LOAD_ORDERS
  COMMENT = 'Root: load a synthetic batch of orders'
AS
EXECUTE IMMEDIATE $$
BEGIN
  LET run_id VARCHAR := SYSTEM$TASK_RUNTIME_INFO('CURRENT_TASK_GRAPH_RUN_GROUP_ID');
  LET bad BOOLEAN := COALESCE(SYSTEM$GET_TASK_GRAPH_CONFIG('inject_bad_rows')::BOOLEAN, FALSE);
  TRUNCATE TABLE RAW_ORDERS;
  INSERT INTO RAW_ORDERS
    SELECT SEQ4() + 1,
           DECODE(UNIFORM(1, 3, RANDOM()), 1, 'EMEA', 2, 'AMER', 'APJ'),
           DECODE(UNIFORM(1, 3, RANDOM()), 1, 'WIDGET', 2, 'GADGET', 'GIZMO'),
           UNIFORM(10, 500, RANDOM()),
           CURRENT_TIMESTAMP()
      FROM TABLE(GENERATOR(ROWCOUNT => 100));
  IF (:bad) THEN
    UPDATE RAW_ORDERS SET AMOUNT = -AMOUNT WHERE ORDER_ID <= 3;
  END IF;
  LET loaded VARCHAR := (SELECT COUNT(*) FROM RAW_ORDERS)::VARCHAR;
  LET detail VARCHAR := 'loaded ' || :loaded || ' rows, inject_bad_rows=' || :bad;
  INSERT INTO PIPELINE_LOG (RUN_ID, TASK_NAME, DETAIL) VALUES (:run_id, 'LOAD_ORDERS', :detail);
  CALL SYSTEM$SET_RETURN_VALUE(:loaded);
END;
$$;

-- Two parallel branches. Each reads the root's return value and returns
-- the number of orders it summarized.
CREATE OR REPLACE TASK DEMO_TASK_GRAPHS.PIPELINE.SUMMARIZE_BY_REGION
  COMMENT = 'Branch: revenue by region'
  AFTER DEMO_TASK_GRAPHS.PIPELINE.LOAD_ORDERS
AS
EXECUTE IMMEDIATE $$
BEGIN
  LET run_id VARCHAR := SYSTEM$TASK_RUNTIME_INFO('CURRENT_TASK_GRAPH_RUN_GROUP_ID');
  LET loaded VARCHAR := SYSTEM$GET_PREDECESSOR_RETURN_VALUE('LOAD_ORDERS');
  DELETE FROM REGION_SUMMARY;
  INSERT INTO REGION_SUMMARY SELECT REGION, COUNT(*), SUM(AMOUNT) FROM RAW_ORDERS GROUP BY REGION;
  LET total VARCHAR := (SELECT SUM(ORDER_COUNT) FROM REGION_SUMMARY)::VARCHAR;
  LET detail VARCHAR := 'root loaded ' || :loaded || ', summarized ' || :total;
  INSERT INTO PIPELINE_LOG (RUN_ID, TASK_NAME, DETAIL) VALUES (:run_id, 'SUMMARIZE_BY_REGION', :detail);
  CALL SYSTEM$SET_RETURN_VALUE(:total);
END;
$$;

CREATE OR REPLACE TASK DEMO_TASK_GRAPHS.PIPELINE.SUMMARIZE_BY_PRODUCT
  COMMENT = 'Branch: revenue by product'
  AFTER DEMO_TASK_GRAPHS.PIPELINE.LOAD_ORDERS
AS
EXECUTE IMMEDIATE $$
BEGIN
  LET run_id VARCHAR := SYSTEM$TASK_RUNTIME_INFO('CURRENT_TASK_GRAPH_RUN_GROUP_ID');
  LET loaded VARCHAR := SYSTEM$GET_PREDECESSOR_RETURN_VALUE('LOAD_ORDERS');
  DELETE FROM PRODUCT_SUMMARY;
  INSERT INTO PRODUCT_SUMMARY SELECT PRODUCT, COUNT(*), SUM(AMOUNT) FROM RAW_ORDERS GROUP BY PRODUCT;
  LET total VARCHAR := (SELECT SUM(ORDER_COUNT) FROM PRODUCT_SUMMARY)::VARCHAR;
  LET detail VARCHAR := 'root loaded ' || :loaded || ', summarized ' || :total;
  INSERT INTO PIPELINE_LOG (RUN_ID, TASK_NAME, DETAIL) VALUES (:run_id, 'SUMMARIZE_BY_PRODUCT', :detail);
  CALL SYSTEM$SET_RETURN_VALUE(:total);
END;
$$;

-- Quality check: joins the two branches, compares their return values and
-- fails the task when the batch has negative amounts.
CREATE OR REPLACE TASK DEMO_TASK_GRAPHS.PIPELINE.CHECK_QUALITY
  COMMENT = 'Quality check: fail when any order has a negative amount'
  AFTER DEMO_TASK_GRAPHS.PIPELINE.SUMMARIZE_BY_REGION, DEMO_TASK_GRAPHS.PIPELINE.SUMMARIZE_BY_PRODUCT
AS
EXECUTE IMMEDIATE $$
DECLARE
  quality_check_failed EXCEPTION (-20001, 'Quality check failed: negative amounts or mismatched branch totals');
BEGIN
  LET run_id VARCHAR := SYSTEM$TASK_RUNTIME_INFO('CURRENT_TASK_GRAPH_RUN_GROUP_ID');
  LET by_region VARCHAR := SYSTEM$GET_PREDECESSOR_RETURN_VALUE('SUMMARIZE_BY_REGION');
  LET by_product VARCHAR := SYSTEM$GET_PREDECESSOR_RETURN_VALUE('SUMMARIZE_BY_PRODUCT');
  LET bad_rows NUMBER := (SELECT COUNT(*) FROM RAW_ORDERS WHERE AMOUNT < 0);
  LET detail VARCHAR := 'region=' || :by_region || ' product=' || :by_product || ' bad_rows=' || :bad_rows;
  INSERT INTO PIPELINE_LOG (RUN_ID, TASK_NAME, DETAIL) VALUES (:run_id, 'CHECK_QUALITY', :detail);
  IF (:bad_rows > 0 OR :by_region <> :by_product) THEN
    RAISE quality_check_failed;
  END IF;
END;
$$;

-- Success path: no WHEN, so it runs only when CHECK_QUALITY succeeds.
CREATE OR REPLACE TASK DEMO_TASK_GRAPHS.PIPELINE.PUBLISH_SUMMARIES
  COMMENT = 'Success path: runs only when the quality check passes'
  AFTER DEMO_TASK_GRAPHS.PIPELINE.CHECK_QUALITY
AS
  INSERT INTO PIPELINE_LOG (RUN_ID, TASK_NAME, DETAIL)
    SELECT SYSTEM$TASK_RUNTIME_INFO('CURRENT_TASK_GRAPH_RUN_GROUP_ID'), 'PUBLISH_SUMMARIES', 'summaries published';

-- Fallback path: advanced branching. Runs only when CHECK_QUALITY failed.
CREATE OR REPLACE TASK DEMO_TASK_GRAPHS.PIPELINE.QUARANTINE_BATCH
  COMMENT = 'Fallback path: runs only when the quality check fails'
  AFTER DEMO_TASK_GRAPHS.PIPELINE.CHECK_QUALITY
  WHEN SYSTEM$PREDECESSORS_STATE('ALL_FAILED')
AS
  INSERT INTO PIPELINE_LOG (RUN_ID, TASK_NAME, DETAIL)
    SELECT SYSTEM$TASK_RUNTIME_INFO('CURRENT_TASK_GRAPH_RUN_GROUP_ID'), 'QUARANTINE_BATCH',
           (SELECT COUNT(*) FROM RAW_ORDERS WHERE AMOUNT < 0) || ' bad rows quarantined';

-- Finalizer: an ordinary task with no AFTER. The graph names it below.
CREATE OR REPLACE TASK DEMO_TASK_GRAPHS.PIPELINE.RECORD_OUTCOME
  COMMENT = 'Finalizer: record the outcome of every run'
AS
  INSERT INTO PIPELINE_LOG (RUN_ID, TASK_NAME, DETAIL)
    SELECT SYSTEM$TASK_RUNTIME_INFO('CURRENT_TASK_GRAPH_RUN_GROUP_ID'), 'RECORD_OUTCOME',
           IFF(COUNT_IF(TASK_NAME = 'PUBLISH_SUMMARIES') > 0, 'outcome=PUBLISHED', 'outcome=QUARANTINED')
      FROM PIPELINE_LOG
     WHERE RUN_ID = SYSTEM$TASK_RUNTIME_INFO('CURRENT_TASK_GRAPH_RUN_GROUP_ID');

-- ------------------------------------------------------------
-- The task graph object. Properties first, then TASK_DEFAULTS
-- (TASK_DEFAULTS must follow every property, and WHEN, if used, comes last).
-- ------------------------------------------------------------
CREATE OR REPLACE TASK GRAPH DEMO_TASK_GRAPHS.PIPELINE.ORDERS_PIPELINE
  SCHEDULE = '720 MINUTE'
  ROOTS = (DEMO_TASK_GRAPHS.PIPELINE.LOAD_ORDERS)
  FINALIZER = DEMO_TASK_GRAPHS.PIPELINE.RECORD_OUTCOME
  CONFIG = $${"inject_bad_rows": false}$$
  COMMENT = 'Orders pipeline: load, summarize, check, publish or quarantine'
  TASK_DEFAULTS (WAREHOUSE = DEMO_TASK_GRAPHS_WH, LOG_LEVEL = 'INFO');

-- Freeze the definition into the first committed version.
ALTER TASK GRAPH DEMO_TASK_GRAPHS.PIPELINE.ORDERS_PIPELINE COMMIT;

SHOW TASK GRAPHS IN SCHEMA DEMO_TASK_GRAPHS.PIPELINE;

-- ------------------------------------------------------------
-- Run it once, now. The graph stays suspended; EXECUTE runs the
-- committed version on demand.
-- ------------------------------------------------------------
EXECUTE TASK GRAPH DEMO_TASK_GRAPHS.PIPELINE.ORDERS_PIPELINE;

-- Give the run about a minute to finish.
CALL SYSTEM$WAIT(60);

-- Capture the graph ID for TASK_HISTORY.
SHOW TASK GRAPHS LIKE 'ORDERS_PIPELINE' IN SCHEMA DEMO_TASK_GRAPHS.PIPELINE;
SET graph_id = (SELECT "id" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));

-- Every task of the latest run, with its state and return value.
SELECT NAME, STATE, RETURN_VALUE, GRAPH_VERSION
  FROM TABLE(DEMO_TASK_GRAPHS.INFORMATION_SCHEMA.TASK_HISTORY(
         GRAPH_ID => $graph_id,
         SCHEDULED_TIME_RANGE_END => CURRENT_TIMESTAMP()))
QUALIFY GRAPH_RUN_GROUP_ID = FIRST_VALUE(GRAPH_RUN_GROUP_ID) OVER (ORDER BY SCHEDULED_TIME DESC)
 ORDER BY SCHEDULED_TIME, NAME;

-- What the tasks wrote for the latest run.
SELECT TASK_NAME, DETAIL
  FROM PIPELINE_LOG
 WHERE RUN_ID = (SELECT RUN_ID FROM PIPELINE_LOG ORDER BY LOGGED_AT DESC LIMIT 1)
 ORDER BY LOGGED_AT;
