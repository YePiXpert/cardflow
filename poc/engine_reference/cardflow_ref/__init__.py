"""CardFlow reference engine (PoC, planning round 2026-10-16).

Purpose: executable semantics for the billing-cycle rules, the per-account cash
timeline, the CP-SAT allocation model and the independent verifier. It is the
golden-fixture oracle for the production engine, NOT production code.

All money is integer minor units (CNY: fen). Rates are Decimal/Fraction.
"""
MODEL_VERSION = "poc-0.1.0"
