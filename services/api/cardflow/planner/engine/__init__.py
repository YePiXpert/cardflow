"""CardFlow planning engine, migrated from the PoC reference engine (T-003).

Executable semantics for the billing-cycle rules, the per-account cash timeline, the
CP-SAT allocation model and the independent verifier. Migrated from
``poc/engine_reference/cardflow_ref`` (planning round 2026-10-16) without semantic
changes; the PoC remains the golden-fixture oracle. Dependencies: standard library and
OR-Tools only -- no web framework, ORM or database driver, and no other ``cardflow``
subpackage (guarded by ``tests/engine/test_dependency_boundary.py``).

All money is integer minor units (CNY: fen). Rates are Decimal/Fraction.

Production changes after the migration (T-004, each covered by a test): the verifier reports
an allocation line for a card outside the plan as an ``UNKNOWN_CARD`` violation; ``plan()``
records a run record (run id, hash of the caller's input taken before any internal
adjustment, model/solver version, time limit, workers, seed) on every outcome and passes
``workers``/``seed`` to every CP-SAT call; ``protocol`` adapts rules-protocol v1 documents.
None of these changes alters a golden result.

Model 1.1.0 (T-004c, engine-spec §12, review wave 3 R3E-01..R3E-22): only actionable
statuses carry a plan; snapshot reflection is judged before the scenario; credit-account and
pool capacity layers; one same-day order for model and verifier; a deterministic tie-break;
fees paid from cash with the repayment; the horizon is the input's (REPAY_AFTER_HORIZON);
the baseline includes the global floor; sensitivity bounded by the run's time limit and
failing item by item; the build-error fallback limited to model building and solving. F-18's
golden results are unchanged.
"""

MODEL_VERSION = "1.1.0"
"""Engine model version recorded in every run record (engine-spec §11). Increment it whenever
the model's semantics change; ``1.0.0`` was the first production release (the PoC was
``poc-0.1.0``), ``1.1.0`` carries the engine-spec §12 rulings (T-004c)."""
