USE ROLE ACCOUNTADMIN;

-- Using ACCOUNTADMIN, create a new role for this exercise and grant to applicable users
CREATE OR REPLACE ROLE TASK_GRAPH_ROLE;
GRANT ROLE TASK_GRAPH_ROLE to USER <YOUR_USER>;
GRANT EXECUTE TASK ON ACCOUNT TO ROLE TASK_GRAPH_ROLE;
GRANT EXECUTE MANAGED TASK ON ACCOUNT TO ROLE TASK_GRAPH_ROLE;
GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE TO ROLE TASK_GRAPH_ROLE;

-- create our virtual warehouse
CREATE OR REPLACE WAREHOUSE TASK_GRAPH_WH AUTO_SUSPEND = 60;

GRANT ALL ON WAREHOUSE TASK_GRAPH_WH TO ROLE TASK_GRAPH_ROLE;

-- Next create a new database and schema,
CREATE OR REPLACE DATABASE TASK_GRAPH_DATABASE;
CREATE OR REPLACE SCHEMA TASK_GRAPH_SCHEMA;

-- Create git integration to load our notebook
CREATE API INTEGRATION IF NOT EXISTS GITHUB_PUBLIC
API_PROVIDER = GIT_HTTPS_API
API_ALLOWED_PREFIXES = ('https://github.com/')
ENABLED = TRUE;

CREATE OR REPLACE GIT REPOSITORY SNOWFLAKE_LABS 
ORIGIN = 'https://github.com/Snowflake-Labs/getting-started-with-task-graphs' 
API_INTEGRATION = 'GITHUB_PUBLIC';

GRANT OWNERSHIP ON DATABASE TASK_GRAPH_DATABASE TO ROLE TASK_GRAPH_ROLE COPY CURRENT GRANTS;
GRANT OWNERSHIP ON ALL SCHEMAS IN DATABASE TASK_GRAPH_DATABASE TO ROLE TASK_GRAPH_ROLE COPY CURRENT GRANTS;
