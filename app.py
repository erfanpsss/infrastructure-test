import argparse


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--first", help="First")
    parser.add_argument("--second", help="Second")
    args = parser.parse_args()
    print(f"APP running. {args.first} - {args.second}")
