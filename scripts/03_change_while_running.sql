/*
  Getting Started with Task Graphs
  03_change_while_running.sql - Act 2: resume the graph, change a task while it
  is resumed, preview the staged change, commit it and run the new version.
*/

USE ROLE DEMO_TASK_GRAPHS_ROLE;
USE SCHEMA DEMO_TASK_GRAPHS.PIPELINE;
USE WAREHOUSE DEMO_TASK_GRAPHS_WH;

-- ------------------------------------------------------------
-- Put the graph on its schedule (every 720 minutes).
-- ------------------------------------------------------------
ALTER TASK GRAPH DEMO_TASK_GRAPHS.PIPELINE.ORDERS_PIPELINE RESUME;

-- ------------------------------------------------------------
-- Change a committed task while the graph is resumed. No suspend needed:
-- the change is staged and the running schedule keeps using the committed
-- version. ALTER TASK ... MODIFY AS replaces the finalizer's body so that it
-- also records the top revenue region.
-- ------------------------------------------------------------
ALTER TASK DEMO_TASK_GRAPHS.PIPELINE.RECORD_OUTCOME MODIFY AS
  INSERT INTO PIPELINE_LOG (RUN_ID, TASK_NAME, DETAIL)
    SELECT SYSTEM$TASK_RUNTIME_INFO('CURRENT_TASK_GRAPH_RUN_GROUP_ID'), 'RECORD_OUTCOME',
           IFF(COUNT_IF(TASK_NAME = 'QUARANTINE_BATCH') > 0, 'outcome=QUARANTINED', 'outcome=PUBLISHED')
           || ' top_region=' || (SELECT MAX_BY(DIMENSION_VALUE, REVENUE) FROM ORDER_SUMMARY WHERE DIMENSION = 'REGION')
      FROM PIPELINE_LOG
     WHERE RUN_ID = SYSTEM$TASK_RUNTIME_INFO('CURRENT_TASK_GRAPH_RUN_GROUP_ID');

-- The graph is STARTED and now has pending changes.
SHOW TASK GRAPHS LIKE 'ORDERS_PIPELINE' IN SCHEMA DEMO_TASK_GRAPHS.PIPELINE
  ->> SELECT "name", "state", "has_pending_changes" FROM $1;

-- Preview exactly what COMMIT would release.
SELECT ENTITY_TYPE, ENTITY_NAME, BEFORE IS NULL AS IS_NEW, AFTER IS NULL AS IS_REMOVED
  FROM TABLE(DEMO_TASK_GRAPHS.INFORMATION_SCHEMA.TASK_GRAPH_CHANGES(
         TASK_GRAPH_NAME => 'DEMO_TASK_GRAPHS.PIPELINE.ORDERS_PIPELINE'));

-- SHOW COMMITTED TASKS reflects what runs: every task still at version 1.
SHOW COMMITTED TASKS IN GRAPH DEMO_TASK_GRAPHS.PIPELINE.ORDERS_PIPELINE
  ->> SELECT "name", "version", "warehouse" FROM $1 ORDER BY "name";

-- ------------------------------------------------------------
-- Release the change and run the new version.
-- ------------------------------------------------------------
ALTER TASK GRAPH DEMO_TASK_GRAPHS.PIPELINE.ORDERS_PIPELINE COMMIT;

SHOW COMMITTED TASKS IN GRAPH DEMO_TASK_GRAPHS.PIPELINE.ORDERS_PIPELINE
  ->> SELECT "name", "version" FROM $1 ORDER BY "name";

EXECUTE TASK GRAPH DEMO_TASK_GRAPHS.PIPELINE.ORDERS_PIPELINE;

CALL SYSTEM$WAIT(60);

SHOW TASK GRAPHS LIKE 'ORDERS_PIPELINE' IN SCHEMA DEMO_TASK_GRAPHS.PIPELINE;
SET graph_id = (SELECT "id" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));

-- The latest run used the new version.
SELECT NAME, STATE, GRAPH_VERSION
  FROM TABLE(DEMO_TASK_GRAPHS.INFORMATION_SCHEMA.TASK_HISTORY(
         GRAPH_ID => $graph_id,
         SCHEDULED_TIME_RANGE_END => CURRENT_TIMESTAMP()))
QUALIFY GRAPH_RUN_GROUP_ID = FIRST_VALUE(GRAPH_RUN_GROUP_ID) OVER (ORDER BY SCHEDULED_TIME DESC)
 ORDER BY SCHEDULED_TIME, NAME;

-- What the changed finalizer logged for that run.
SELECT TASK_NAME, DETAIL
  FROM PIPELINE_LOG
 WHERE RUN_ID = (SELECT RUN_ID FROM PIPELINE_LOG ORDER BY LOGGED_AT DESC LIMIT 1)
   AND TASK_NAME = 'RECORD_OUTCOME';
