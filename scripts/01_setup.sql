/*
  Getting Started with Task Graphs
  01_setup.sql - a demo role, then the warehouse, database, schema and the
  three demo tables, all owned by that role.
  Run this first, top to bottom. To start over, run 05_cleanup.sql, then this.
*/

-- ------------------------------------------------------------
-- A least-privilege role for the guide. Only these grants need ACCOUNTADMIN.
-- The member tasks run on the graph's warehouse, but a task created without
-- a WAREHOUSE is checked for the serverless privilege at CREATE time, so the
-- role needs EXECUTE MANAGED TASK as well as EXECUTE TASK.
-- The task error alert (02) needs EXECUTE ALERT to run, and the
-- SNOWFLAKE.EVENTS_VIEWER application role to read task events.
-- MODIFY LOG EVENT LEVEL lets the role turn on task event logging for its
-- own database; owning the database is not enough.
-- ------------------------------------------------------------
USE ROLE ACCOUNTADMIN;

CREATE ROLE IF NOT EXISTS DEMO_TASK_GRAPHS_ROLE
  COMMENT = 'Getting Started with Task Graphs: owns every object the guide creates';
GRANT CREATE DATABASE ON ACCOUNT TO ROLE DEMO_TASK_GRAPHS_ROLE;
GRANT CREATE WAREHOUSE ON ACCOUNT TO ROLE DEMO_TASK_GRAPHS_ROLE;
GRANT EXECUTE TASK ON ACCOUNT TO ROLE DEMO_TASK_GRAPHS_ROLE;
GRANT EXECUTE MANAGED TASK ON ACCOUNT TO ROLE DEMO_TASK_GRAPHS_ROLE;
GRANT EXECUTE ALERT ON ACCOUNT TO ROLE DEMO_TASK_GRAPHS_ROLE;
GRANT APPLICATION ROLE SNOWFLAKE.EVENTS_VIEWER TO ROLE DEMO_TASK_GRAPHS_ROLE;
GRANT MODIFY LOG EVENT LEVEL ON ACCOUNT TO ROLE DEMO_TASK_GRAPHS_ROLE;
GRANT ROLE DEMO_TASK_GRAPHS_ROLE TO ROLE SYSADMIN;

SET MY_USER = CURRENT_USER();
GRANT ROLE DEMO_TASK_GRAPHS_ROLE TO USER IDENTIFIER($MY_USER);

-- ------------------------------------------------------------
-- Everything from here on runs as the demo role
-- ------------------------------------------------------------
USE ROLE DEMO_TASK_GRAPHS_ROLE;

CREATE WAREHOUSE IF NOT EXISTS DEMO_TASK_GRAPHS_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Getting Started with Task Graphs: compute for every member task';

CREATE DATABASE IF NOT EXISTS DEMO_TASK_GRAPHS
  COMMENT = 'Getting Started with Task Graphs: demo database';

-- Log task events (every run's status) so the task error alert can see them.
ALTER DATABASE DEMO_TASK_GRAPHS SET LOG_EVENT_LEVEL = 'INFO';

CREATE OR REPLACE SCHEMA DEMO_TASK_GRAPHS.PIPELINE
  COMMENT = 'Getting Started with Task Graphs: tables, tasks and the task graph';

USE SCHEMA DEMO_TASK_GRAPHS.PIPELINE;
USE WAREHOUSE DEMO_TASK_GRAPHS_WH;

-- ------------------------------------------------------------
-- Tables
-- ------------------------------------------------------------
CREATE OR REPLACE TABLE RAW_ORDERS (
  ORDER_ID  NUMBER,
  REGION    VARCHAR,
  PRODUCT   VARCHAR,
  AMOUNT    NUMBER(10,2),
  LOADED_AT TIMESTAMP_LTZ
) COMMENT = 'Synthetic order batch, reloaded by the root task on every run';

CREATE OR REPLACE TABLE ORDER_SUMMARY (
  DIMENSION       VARCHAR,
  DIMENSION_VALUE VARCHAR,
  ORDER_COUNT     NUMBER,
  REVENUE         NUMBER(12,2)
) COMMENT = 'Revenue by region and by product; each branch writes its own DIMENSION rows';

CREATE OR REPLACE TABLE PIPELINE_LOG (
  RUN_ID    VARCHAR,
  TASK_NAME VARCHAR,
  DETAIL    VARCHAR,
  LOGGED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
) COMMENT = 'One row per task step, keyed by the graph run group ID';

SHOW TABLES IN SCHEMA DEMO_TASK_GRAPHS.PIPELINE;
