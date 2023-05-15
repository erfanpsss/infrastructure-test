import argparse
import logging
from settings import TEST_ENV

logging.basicConfig(
    format='[%(levelname)s]: %(asctime)s - %(name)s - %(funcName)s:%(lineno)d - %(message)s',
    level=logging.INFO,
    handlers=[
        logging.FileHandler("debug.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--first", help="First")
    parser.add_argument("--second", help="Second")
    args = parser.parse_args()
    logger.info(f"APP running. {args.first} - {args.second} test env: {TEST_ENV}")
