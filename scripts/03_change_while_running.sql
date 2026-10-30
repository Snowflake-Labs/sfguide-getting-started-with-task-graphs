/*
  Getting Started with Task Graphs
  03_change_while_running.sql - Act 2: resume the graph, add a task while it
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
-- Add a task while the graph is resumed. No suspend needed: the change is
-- staged and the running schedule keeps using the committed version.
-- ------------------------------------------------------------
CREATE TASK IF NOT EXISTS DEMO_TASK_GRAPHS.PIPELINE.FLAG_TOP_REGION
  COMMENT = 'Added while resumed: log the top revenue region'
  AFTER DEMO_TASK_GRAPHS.PIPELINE.PUBLISH_SUMMARIES
AS
  INSERT INTO PIPELINE_LOG (RUN_ID, TASK_NAME, DETAIL)
    SELECT SYSTEM$TASK_RUNTIME_INFO('CURRENT_TASK_GRAPH_RUN_GROUP_ID'), 'FLAG_TOP_REGION', 'top region ' || REGION
      FROM REGION_SUMMARY
     ORDER BY REVENUE DESC
     LIMIT 1;

-- The graph is STARTED and now has pending changes.
SHOW TASK GRAPHS LIKE 'ORDERS_PIPELINE' IN SCHEMA DEMO_TASK_GRAPHS.PIPELINE
  ->> SELECT "name", "state", "has_pending_changes" FROM $1;

-- Preview exactly what COMMIT would release.
SELECT ENTITY_TYPE, ENTITY_NAME, BEFORE IS NULL AS IS_NEW, AFTER IS NULL AS IS_REMOVED
  FROM TABLE(DEMO_TASK_GRAPHS.INFORMATION_SCHEMA.TASK_GRAPH_CHANGES(
         TASK_GRAPH_NAME => 'DEMO_TASK_GRAPHS.PIPELINE.ORDERS_PIPELINE'));

-- SHOW TASKS reflects the staged edit: 8 tasks.
SHOW TASKS IN SCHEMA DEMO_TASK_GRAPHS.PIPELINE
  ->> SELECT "name", "predecessors" FROM $1 ORDER BY "name";

-- SHOW COMMITTED TASKS reflects what runs: still 7 tasks.
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

-- The latest run used the new version and ran FLAG_TOP_REGION.
SELECT NAME, STATE, GRAPH_VERSION
  FROM TABLE(DEMO_TASK_GRAPHS.INFORMATION_SCHEMA.TASK_HISTORY(
         GRAPH_ID => $graph_id,
         SCHEDULED_TIME_RANGE_END => CURRENT_TIMESTAMP()))
QUALIFY GRAPH_RUN_GROUP_ID = FIRST_VALUE(GRAPH_RUN_GROUP_ID) OVER (ORDER BY SCHEDULED_TIME DESC)
 ORDER BY SCHEDULED_TIME, NAME;
