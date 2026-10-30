[![Snowflake - Certified](https://img.shields.io/badge/Snowflake-Certified-2ea44f?style=for-the-badge&logo=snowflake)](https://developers.snowflake.com/solutions/)

# Getting Started with Task Graphs

## Overview

This repository holds the SQL scripts for the [Getting Started with Task Graphs](https://www.snowflake.com/en/developers/guides/getting-started-with-task-graphs/) guide.

You build one task graph object, ORDERS_PIPELINE, that loads a synthetic batch of orders, summarizes it in two parallel branches that pass return values, checks the result, and then either publishes the summaries or quarantines the batch. A finalizer records the outcome of every run. You then add a task while the graph is resumed, commit the change, and force one bad batch so the fallback branch runs.

Everything runs in a Snowsight workspace on 100 rows of generated data. There are no external dependencies.

## What You'll Learn

- How to create a task graph object with a schedule, a finalizer, CONFIG and TASK_DEFAULTS
- How to pass return values between parallel branches
- How to branch on failure with SYSTEM$PREDECESSORS_STATE
- How COMMIT, EXECUTE TASK GRAPH and committed versions work
- How to change a resumed graph, inspect the change with TASK_GRAPH_CHANGES and release it
- How to inspect runs with TASK_HISTORY and COMPLETE_TASK_GRAPHS

## Prerequisites

- A Snowflake account and access to the ACCOUNTADMIN role for the first statements of 01_setup.sql, which create DEMO_TASK_GRAPHS_ROLE. Everything else runs as that role

## Getting Started

1. Navigate to **Projects > Workspaces** in Snowsight.
2. Click **Create** (+) and select **Git repository**.
3. Enter the repository URL: `https://github.com/Snowflake-Labs/sfguide-getting-started-with-task-graphs`
4. Select an API Integration for GitHub ([create one if needed](https://docs.snowflake.com/en/user-guide/ui-snowsight/workspaces-git#label-create-a-git-workspace)).
5. Select **Public repository**.

Then run the scripts in order:

| File | What it does |
|:-----|:-------------|
| scripts/01_setup.sql | Creates the demo role, then the warehouse, database, schema and tables |
| scripts/02_build_task_graph.sql | Creates the member tasks and the graph, commits it, runs it once |
| scripts/03_change_while_running.sql | Resumes the graph, adds a task, previews and commits the change |
| scripts/04_force_failure.sql | Runs one bad batch, shows the fallback and finalizer, retires a task, suspends the graph |
| scripts/05_cleanup.sql | Drops everything the guide created, including the role |

To start over, run 05_cleanup.sql and then 01_setup.sql.

To run them from a terminal with the [Snowflake CLI](https://docs.snowflake.com/en/developer-guide/snowflake-cli/index) instead:

```bash
snow sql -f scripts/01_setup.sql
snow sql -f scripts/02_build_task_graph.sql
snow sql -f scripts/03_change_while_running.sql
snow sql -f scripts/04_force_failure.sql
snow sql -f scripts/05_cleanup.sql
```

## Repository Structure

```
sfguide-getting-started-with-task-graphs/
├── README.md
├── LICENSE
├── LEGAL.md
└── scripts/
    ├── 01_setup.sql
    ├── 02_build_task_graph.sql
    ├── 03_change_while_running.sql
    ├── 04_force_failure.sql
    └── 05_cleanup.sql
```

## Related Resources

- [Declare Task Graph as an object](https://docs.snowflake.com/en/user-guide/task-graph-object)
- [CREATE TASK GRAPH](https://docs.snowflake.com/en/sql-reference/sql/create-task-graph)
- [ALTER TASK GRAPH](https://docs.snowflake.com/en/sql-reference/sql/alter-task-graph)
- [Control when tasks run with advanced branching](https://docs.snowflake.com/en/user-guide/tasks-graphs#label-task-graph-advanced-branching)

## License

Licensed under the Apache License 2.0. See [LICENSE](LICENSE) and [LEGAL.md](LEGAL.md).
