# Getting Started with Task Graphs

## Overview

With [task graphs](https://docs.snowflake.com/en/user-guide/tasks-graphs) you can automatically run sequences of tasks. A task graph, or directed acyclic graph (DAG), is a series of tasks composed of a root task and child tasks, organized by their dependencies. Task graphs flow in a single direction, meaning a task later in the series cannot prompt the run of an earlier task. Each task can depend on multiple other tasks and won’t run until they all complete. Each task can also have multiple child tasks that depend on it.

This quickstart sets up an example task graph to showcase its features. 

## Step-By-Step Guide

For prerequisites, environment setup, step-by-step guide and instructions, please refer to the [QuickStart Guide](https://quickstarts.snowflake.com/guide/getting-started-with-task-graphs/index.html).