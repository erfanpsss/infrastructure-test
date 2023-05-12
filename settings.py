from dotenv import load_dotenv
import os

load_dotenv()

# Loggings
LOGGING_EXCUDED_LOG_LEVEL_NAMES = [item.strip().upper() for item in os.environ.get("LOGGING_EXCUDED_LOG_LEVEL_NAMES", "").split(",")]

# MariaDB
DATABASE_HOST=os.environ.get("DATABASE_HOST")
DATABASE_NAME=os.environ.get("DATABASE_NAME")
DATABASE_USER=os.environ.get("DATABASE_USER")
DATABASE_PORT=os.environ.get("DATABASE_PORT")
DATABASE_PASSWORD=os.environ.get("DATABASE_PASSWORD")
DB_PROPERTIES = {
    'host': DATABASE_HOST,
    'dbname': DATABASE_NAME,
    'user': DATABASE_USER,
    'port': DATABASE_PORT,
    'pwd': DATABASE_PASSWORD
}
