from dotenv import load_dotenv
import os

load_dotenv()

# Loggings
LOGGING_EXCUDED_LOG_LEVEL_NAMES = [
    item.strip().upper() for item in os.environ.get(
        "LOGGING_EXCUDED_LOG_LEVEL_NAMES", ""
    ).split(",")
]