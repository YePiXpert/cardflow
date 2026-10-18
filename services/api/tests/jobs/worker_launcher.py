"""Run the real ``cardflow`` command line with the testkit job kinds registered.

Used by ``test_cli_worker.py`` and the T-008 worker demo; never by production code::

    python tests/jobs/worker_launcher.py worker --concurrency 2

The kinds (``$CARDFLOW_TESTKIT_PREFIX.*``, default ``test``) are registered on the
production registry object *of this process only*, then ``cardflow.cli.main`` runs exactly
as the ``cardflow`` console script would. Spawned job children re-import this file as
``__mp_main__``; the registration below the ``__main__`` guard does not run there.
"""

import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import jobs_testkit

from cardflow.cli import main
from cardflow.jobs.registry import REGISTRY

if __name__ == "__main__":
    jobs_testkit.register_all(REGISTRY, prefix=os.environ.get("CARDFLOW_TESTKIT_PREFIX", "test"))
    raise SystemExit(main(sys.argv[1:]))
