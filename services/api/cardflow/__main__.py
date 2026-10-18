"""Allow ``python -m cardflow`` as an alias for the ``cardflow`` console script."""

from cardflow.cli import main

raise SystemExit(main())
