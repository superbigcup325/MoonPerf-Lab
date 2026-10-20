"""Allow ``python -m mpf``."""

import sys

from mpf.cli import main

if __name__ == "__main__":
    sys.exit(main())
