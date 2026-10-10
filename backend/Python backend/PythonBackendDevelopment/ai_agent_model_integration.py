from langchain_community.utilities import SQLDatabase
from langchain_community.agent_toolkits import create_sql_agent
from langchain_qwq.chat_models import ChatQwen

# Define the agent with model flash for Chat Qwen (from Alibaba Cloud)
defined_model = ChatQwen(model="qwen-flash")
