"""Validate generated B2 APIs and macros against the independent Clang oracle."""

from check_a64_generated import main


if __name__ == "__main__":
    main(default_batch="B2")
