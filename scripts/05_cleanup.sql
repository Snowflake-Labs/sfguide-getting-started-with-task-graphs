/*
  Getting Started with Task Graphs
  05_cleanup.sql - drop everything this guide created, including the demo role.
  Safe to run at any point, and again after everything is gone.
*/

-- ACCOUNTADMIN inherits DEMO_TASK_GRAPHS_ROLE through SYSADMIN, so it can drop
-- the role's objects, and the script still works after the role is gone.
USE ROLE ACCOUNTADMIN;

-- Dropping the database removes the schema, the task graph, its member tasks
-- and the tables, whether or not the graph is resumed.
DROP DATABASE IF EXISTS DEMO_TASK_GRAPHS;
DROP WAREHOUSE IF EXISTS DEMO_TASK_GRAPHS_WH;
DROP ROLE IF EXISTS DEMO_TASK_GRAPHS_ROLE;
