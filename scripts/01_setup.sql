/*
  Getting Started with Task Graphs
  01_setup.sql - a demo role, then the warehouse, database, schema and the
  four demo tables, all owned by that role.
  Run this first, top to bottom. To start over, run 05_cleanup.sql, then this.
*/

-- ------------------------------------------------------------
-- A least-privilege role for the guide. Only these grants need ACCOUNTADMIN.
-- The member tasks run on the graph's warehouse, but a task created without
-- a WAREHOUSE is checked for the serverless privilege at CREATE time, so the
-- role needs EXECUTE MANAGED TASK as well as EXECUTE TASK.
-- ------------------------------------------------------------
USE ROLE ACCOUNTADMIN;

CREATE ROLE IF NOT EXISTS DEMO_TASK_GRAPHS_ROLE
  COMMENT = 'Getting Started with Task Graphs: owns every object the guide creates';
GRANT CREATE DATABASE ON ACCOUNT TO ROLE DEMO_TASK_GRAPHS_ROLE;
GRANT CREATE WAREHOUSE ON ACCOUNT TO ROLE DEMO_TASK_GRAPHS_ROLE;
GRANT EXECUTE TASK ON ACCOUNT TO ROLE DEMO_TASK_GRAPHS_ROLE;
GRANT EXECUTE MANAGED TASK ON ACCOUNT TO ROLE DEMO_TASK_GRAPHS_ROLE;
GRANT ROLE DEMO_TASK_GRAPHS_ROLE TO ROLE SYSADMIN;

SET my_user = CURRENT_USER();
GRANT ROLE DEMO_TASK_GRAPHS_ROLE TO USER IDENTIFIER($my_user);

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

CREATE OR REPLACE TABLE REGION_SUMMARY (
  REGION      VARCHAR,
  ORDER_COUNT NUMBER,
  REVENUE     NUMBER(12,2)
) COMMENT = 'Revenue by region, written by SUMMARIZE_BY_REGION';

CREATE OR REPLACE TABLE PRODUCT_SUMMARY (
  PRODUCT     VARCHAR,
  ORDER_COUNT NUMBER,
  REVENUE     NUMBER(12,2)
) COMMENT = 'Revenue by product, written by SUMMARIZE_BY_PRODUCT';

CREATE OR REPLACE TABLE PIPELINE_LOG (
  RUN_ID    VARCHAR,
  TASK_NAME VARCHAR,
  DETAIL    VARCHAR,
  LOGGED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
) COMMENT = 'One row per task step, keyed by the graph run group ID';

SHOW TABLES IN SCHEMA DEMO_TASK_GRAPHS.PIPELINE;
