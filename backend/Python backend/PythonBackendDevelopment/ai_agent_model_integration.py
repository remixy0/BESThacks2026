from langchain_community.utilities import SQLDatabase
from langchain_community.agent_toolkits import create_sql_agent
from langchain_qwq.chat_models import ChatQwen

# Define the agent with model flash for Chat Qwen (from Alibaba Cloud), the database and the agent
defined_model = ChatQwen(model="qwen-flash")
database = SQLDatabase("postgresql://user:password@server_ip/db_name")
agent_defined = create_sql_agent(defined_model, db=database, agent_type="tool-calling")
agent_defined.invoke("query")
