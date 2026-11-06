/*
  Getting Started with Task Graphs
  04_force_failure.sql - Act 3: run once with bad data so PUBLISH_SUMMARIES
  fails, watch the fallback branch, the finalizer and the task error alert,
  then park the graph.
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

-- PUBLISH_SUMMARIES failed and the fallback ran.
SELECT NAME, STATE, ERROR_MESSAGE
  FROM TABLE(DEMO_TASK_GRAPHS.INFORMATION_SCHEMA.TASK_HISTORY(
         GRAPH_ID => $graph_id,
         SCHEDULED_TIME_RANGE_END => CURRENT_TIMESTAMP()))
QUALIFY GRAPH_RUN_GROUP_ID = FIRST_VALUE(GRAPH_RUN_GROUP_ID) OVER (ORDER BY SCHEDULED_TIME DESC)
 ORDER BY SCHEDULED_TIME, NAME;

-- The payoff: every run so far, side by side.
SELECT MIN(LOGGED_AT) AS RUN_STARTED,
       MAX(IFF(TASK_NAME = 'LOAD_ORDERS', DETAIL, NULL)) AS LOADED,
       MAX(IFF(TASK_NAME = 'PUBLISH_SUMMARIES', DETAIL, NULL)) AS PUBLISH,
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
-- The task error alert. The template ignores task events from the last
-- 60 seconds, so wait for the failure to age past that, run the alert now
-- instead of waiting for its schedule, then read its history.
-- ------------------------------------------------------------
CALL SYSTEM$WAIT(90);

EXECUTE ALERT DEMO_TASK_GRAPHS.PIPELINE.TASK_ERROR_RATE;

CALL SYSTEM$WAIT(30);

SELECT NAME, STATE, SQL_ERROR_MESSAGE
  FROM TABLE(DEMO_TASK_GRAPHS.INFORMATION_SCHEMA.ALERT_HISTORY(
         SCHEDULED_TIME_RANGE_START => DATEADD('HOUR', -1, CURRENT_TIMESTAMP()),
         ALERT_NAME => 'TASK_ERROR_RATE'))
 ORDER BY SCHEDULED_TIME DESC;

-- ------------------------------------------------------------
-- Park the graph: no more scheduled runs.
-- ------------------------------------------------------------
ALTER TASK GRAPH DEMO_TASK_GRAPHS.PIPELINE.ORDERS_PIPELINE SUSPEND;

SHOW TASK GRAPHS LIKE 'ORDERS_PIPELINE' IN SCHEMA DEMO_TASK_GRAPHS.PIPELINE
  ->> SELECT "name", "state", "has_pending_changes" FROM $1;
