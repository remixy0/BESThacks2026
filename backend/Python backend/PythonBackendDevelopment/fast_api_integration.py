# The "BestHacks2026" museum Python backend functionality combining FastAPI and SQL_Alchemy

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.ext.declarative import declarative_base
from fastapi import Depends, FastAPI, HTTPException
from sqlalchemy import Column, Integer, String, DateTime, Float, ForeignKey
from pydantic import BaseModel

# Connecting to database
connection_to_the_database = "postgresql://postgres:postgres@127.0.0.1/chicago_fmonh_exhibitional_and_artefact_data"

# Creating the engine with the connection string --> creating a session to connect to database
# Creating the base for models and schemes
engine = create_engine(connection_to_the_database)
LocalSession = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

# Binding the engine of database to the base class
Base.metadata.create_all(bind=engine)

# Creating the Database sessions instance
def getting_database():
    database = LocalSession()
    try:
        yield database
    finally:
        database.close()

application = FastAPI()
@application.get("/") # Informacje o eksponacie w muzeum
def read_the_database(db:Session = Depends(detting_database)):
    users = database.query().all()
    return users

# This is only the pre-functionality