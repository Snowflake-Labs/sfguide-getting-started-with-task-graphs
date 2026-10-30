/*
  Getting Started with Task Graphs
  04_force_failure.sql - Act 3: run once with bad data so the quality check
  fails, watch the fallback branch and the finalizer, then retire a task and
  park the graph.
*/

USE ROLE DEMO_TASK_GRAPHS_ROLE;
USE SCHEMA DEMO_TASK_GRAPHS.PIPELINE;
USE WAREHOUSE DEMO_TASK_GRAPHS_WH;

-- ------------------------------------------------------------
-- One run with bad data. USING CONFIG overrides the graph's CONFIG for this
-- run only; the graph definition keeps inject_bad_rows = false.
-- ------------------------------------------------------------
EXECUTE TASK GRAPH DEMO_TASK_GRAPHS.PIPELINE.ORDERS_PIPELINE
  USING CONFIG = $${"inject_bad_rows": true}$$;

CALL SYSTEM$WAIT(60);

SHOW TASK GRAPHS LIKE 'ORDERS_PIPELINE' IN SCHEMA DEMO_TASK_GRAPHS.PIPELINE;
SET graph_id = (SELECT "id" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));

-- CHECK_QUALITY failed, the success path was skipped, the fallback ran.
SELECT NAME, STATE, ERROR_MESSAGE
  FROM TABLE(DEMO_TASK_GRAPHS.INFORMATION_SCHEMA.TASK_HISTORY(
         GRAPH_ID => $graph_id,
         SCHEDULED_TIME_RANGE_END => CURRENT_TIMESTAMP()))
QUALIFY GRAPH_RUN_GROUP_ID = FIRST_VALUE(GRAPH_RUN_GROUP_ID) OVER (ORDER BY SCHEDULED_TIME DESC)
 ORDER BY SCHEDULED_TIME, NAME;

-- The payoff: every run so far, side by side.
SELECT MIN(LOGGED_AT) AS RUN_STARTED,
       MAX(IFF(TASK_NAME = 'LOAD_ORDERS', DETAIL, NULL)) AS LOADED,
       MAX(IFF(TASK_NAME = 'CHECK_QUALITY', DETAIL, NULL)) AS QUALITY_CHECK,
       BOOLOR_AGG(TASK_NAME = 'PUBLISH_SUMMARIES') AS PUBLISHED,
       BOOLOR_AGG(TASK_NAME = 'QUARANTINE_BATCH') AS QUARANTINED,
       MAX(IFF(TASK_NAME = 'RECORD_OUTCOME', DETAIL, NULL)) AS FINALIZER
  FROM PIPELINE_LOG
 GROUP BY RUN_ID
 ORDER BY RUN_STARTED;

-- The graph run itself is reported as FAILED, with the task that failed first.
-- GRAPH_NAME takes the bare name and also matches earlier graphs of the same
-- name, so keep only this graph's runs.
SELECT STATE, GRAPH_VERSION, FIRST_ERROR_TASK_NAME
  FROM TABLE(DEMO_TASK_GRAPHS.INFORMATION_SCHEMA.COMPLETE_TASK_GRAPHS(
         GRAPH_NAME => 'ORDERS_PIPELINE'))
 WHERE GRAPH_ID = $graph_id
 ORDER BY SCHEDULED_TIME DESC;

-- ------------------------------------------------------------
-- Retire FLAG_TOP_REGION. A task in the committed version of a resumed graph
-- can't be dropped: sever it, commit, then drop. IF EXISTS lets the script
-- run again after FLAG_TOP_REGION is gone.
-- ------------------------------------------------------------
ALTER TASK IF EXISTS DEMO_TASK_GRAPHS.PIPELINE.FLAG_TOP_REGION
  REMOVE AFTER DEMO_TASK_GRAPHS.PIPELINE.PUBLISH_SUMMARIES;

SELECT ENTITY_TYPE, ENTITY_NAME, BEFORE IS NULL AS IS_NEW, AFTER IS NULL AS IS_REMOVED
  FROM TABLE(DEMO_TASK_GRAPHS.INFORMATION_SCHEMA.TASK_GRAPH_CHANGES(
         TASK_GRAPH_NAME => 'DEMO_TASK_GRAPHS.PIPELINE.ORDERS_PIPELINE'));

ALTER TASK GRAPH DEMO_TASK_GRAPHS.PIPELINE.ORDERS_PIPELINE COMMIT;

DROP TASK IF EXISTS DEMO_TASK_GRAPHS.PIPELINE.FLAG_TOP_REGION;

-- ------------------------------------------------------------
-- Park the graph: no more scheduled runs.
-- ------------------------------------------------------------
ALTER TASK GRAPH DEMO_TASK_GRAPHS.PIPELINE.ORDERS_PIPELINE SUSPEND;

SHOW TASK GRAPHS LIKE 'ORDERS_PIPELINE' IN SCHEMA DEMO_TASK_GRAPHS.PIPELINE
  ->> SELECT "name", "state", "has_pending_changes" FROM $1;
