"""Differential and property test of the engine against an independent reference (T-004c).

Review R3E-06 / R3E-16 (engine-spec §12): the wave-3 review's differential experiment, brought
into the repository. ``diff_reference.py`` (same directory, no ``cardflow`` import) computes
by brute force what the engine must answer for small random protocol documents; this test runs
the engine through the protocol (``plan_from_protocol`` / ``verify_from_protocol``) on the same
documents and compares:

* C1  the outcome validates against ``PlanOutcome.schema.json`` (strict integers, no float);
* C2  NEEDS_DATA exactly when the reference finds a data issue, with the same codes;
* C3  baseline ok per scenario (accounts AND global floor, §12.8); BASELINE_SHORTFALL exactly
      when the decision baseline fails;
* C4  no eligible card -> INFEASIBLE, solver NOT_RUN, the reference exclusion of every card;
* C5  soundness: verify(solve(x)) -- an actionable allocation passes the reference structure
      and decision-scenario check; MODEL_INVALID never occurs;
* C6  completeness: INFEASIBLE exactly when no allocation is feasible (brute force);
* C7  the tier values equal the reference objective vector, and the allocation IS the
      reference's canonical one (lexicographically largest in card order among the optima,
      §12.5) -- one allocation per input;
* C8  business status and failing scenarios;
* C9  every scenario check of the verification and every allocation line;
* C10 rejection reasons (§12: REPAY_AFTER_HORIZON, MIN_SPLIT_ABOVE_AMOUNT, NOT_COMPARED);
* C11 random allocations through the solver-free verifier: ok, structural_ok, every check;
* C12 the same document with ``workers`` 1 and 8 gives the same outcome (run id and timing
      fields aside), sensitivity included;
* C13 sensitivity (subset): least extra cash, largest affordable amount, first feasible
      later date, each with its canonical allocation.

Default run: fixed seeds, bounded to about a minute. ``CARDFLOW_ENGINE_FUZZ=1`` runs a larger
sample (more instances and seeds; ``CARDFLOW_ENGINE_FUZZ_N`` instances per seed).
"""

import copy
import importlib.util
import json
import os
import random
import sys
import time
from collections import Counter
from pathlib import Path
from types import ModuleType
from typing import Any

import pytest

from cardflow.planner.engine.protocol import (
    ProtocolError,
    inputs_from_protocol,
    plan_from_protocol,
    verify_from_protocol,
)

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
FUZZ = os.environ.get("CARDFLOW_ENGINE_FUZZ") == "1"
SEEDS = (
    (20261017, 20261018, 20261019, 20261020, 20261021, 20261022)
    if FUZZ
    else (20261017, 20261018, 20261019)
)
PER_SEED = int(os.environ.get("CARDFLOW_ENGINE_FUZZ_N", "2000")) if FUZZ else 400
SENSITIVITY_EVERY = 1  # C13 on every instance whose run computed sensitivity
DETERMINISM_EVERY = 2  # C12 on every second instance
VOLATILE = ("run_id", "created_at", "wall_time_s", "input_hash")

type Doc = dict[str, Any]


def _load(name: str, path: Path) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


ref = _load("engine_diff_reference", HERE / "diff_reference.py")
runner = _load(
    "engine_diff_runner", REPO / "packages" / "rules-protocol" / "runner_py" / "run_fixtures.py"
)
REGISTRY = runner.load_registry()


def stable(out: Doc) -> str:
    o = {k: v for k, v in out.items() if k not in VOLATILE}
    o["tiers"] = [{k: v for k, v in t.items() if k != "wall_time_s"} for t in o["tiers"]]
    o.pop("workers", None)
    return json.dumps(o, sort_keys=True, ensure_ascii=False)


class Mismatches:
    def __init__(self) -> None:
        self.found: list[dict[str, Any]] = []
        self.stats: Counter[str] = Counter()

    def add(self, check: str, seed: int, i: int, doc: Doc, detail: object) -> None:
        self.stats[f"MISMATCH {check}"] += 1
        if len(self.found) < 8:
            self.found.append({"check": check, "seed": seed, "i": i, "detail": detail, "doc": doc})


def _iso_map(d: dict[str, Any]) -> dict[str, Any]:
    return {k: v.isoformat() if hasattr(v, "isoformat") else v for k, v in d.items()}


def _compare_instance(
    doc: Doc, seed: int, i: int, bad: Mismatches, *, sensitivity: bool, determinism: bool
) -> None:
    stats = bad.stats
    out = plan_from_protocol(copy.deepcopy(doc))
    stats[f"status {out['business_status']}"] += 1
    stats[f"solver {out['solver_status']}"] += 1
    errors = runner.schema_errors(REGISTRY, "PlanOutcome.schema.json", out)  # C1
    if errors:
        bad.add("C1 outcome schema", seed, i, doc, errors[:3])
    if runner.find_floats(out) and {
        p
        for p in runner.find_floats(out)
        if p not in ("/time_limit_s", "/wall_time_s") and not p.endswith("/wall_time_s")
    }:
        bad.add("C1 float in outcome", seed, i, doc, runner.find_floats(out))
    if determinism:  # C12: any workers, same answer (sensitivity included)
        other = copy.deepcopy(doc)
        other["options"]["workers"] = 1 if doc["options"]["workers"] != 1 else 8
        again = plan_from_protocol(other)
        stats["C12 workers 1 vs 8"] += 1
        if stable(again) != stable(out):
            bad.add("C12 nondeterministic", seed, i, doc, "outcome differs with other workers")
    exp = ref.expected(doc)
    got_codes = {d["code"] for d in out["data_issues"]}
    if (out["business_status"] == "NEEDS_DATA") != (exp.status == "NEEDS_DATA") or (
        exp.issues and got_codes != exp.issues
    ):  # C2
        bad.add("C2 needs data", seed, i, doc, [sorted(got_codes), sorted(exp.issues)])
        return
    if exp.status == "NEEDS_DATA":
        return
    stats["evaluated"] += 1
    for sid, ok in exp.baseline_ok.items():  # C3
        eng = out["baseline"].get(sid)
        global_breach = bool(eng and eng.get("global_breaches"))  # presence: C1 (schema)
        if eng is None or eng["ok"] != ok or global_breach != exp.baseline_global[sid]:
            bad.add("C3 baseline", seed, i, doc, [sid, eng and eng["ok"], ok])
    if exp.status == "BASELINE_SHORTFALL" or out["business_status"] == "BASELINE_SHORTFALL":
        if out["business_status"] != exp.status:
            bad.add("C3 shortfall", seed, i, doc, [out["business_status"], exp.status])
        return
    rejections = {r["card_id"]: r["reason"] for r in out["rejections"]}
    if exp.status == "INFEASIBLE" and not exp.feasible and all(c.reason for c in exp.cards):  # C4
        stats["no eligible card"] += 1
        ok = (
            out["business_status"] == "INFEASIBLE"
            and out["solver_status"] == "NOT_RUN"
            and any(n.startswith("NO_ELIGIBLE_CARDS") for n in out["notes"])
        )
        if not ok or rejections != exp.rejections:
            bad.add("C4 no eligible", seed, i, doc, [out["business_status"], rejections])
        return
    status = out["business_status"]
    if status == "MODEL_INVALID":  # C5
        bad.add("C5 model invalid", seed, i, doc, out["notes"])
        return
    if (status == "INFEASIBLE") != (exp.status == "INFEASIBLE"):  # C6
        bad.add("C6 completeness", seed, i, doc, [status, exp.status, len(exp.feasible)])
        return
    if status == "UNKNOWN":
        bad.add("C6 unknown on a tiny instance", seed, i, doc, out["notes"])
        return
    if rejections != exp.rejections:  # C10
        bad.add("C10 rejections", seed, i, doc, [rejections, exp.rejections])
    by_id = {c.id: c for c in exp.cards}
    scenarios = {s["scenario_id"]: s for s in doc["scenarios"]}
    decision = doc["options"]["decision_scenario"]
    if status == "INFEASIBLE":
        stats["infeasible (proved)"] += 1
        if sensitivity and doc["options"]["decision_scenario"] in out["sensitivity"]:
            _compare_sensitivity(doc, out, decision, exp, seed, i, bad)
        return
    alloc = {a["card_id"]: a["amount_minor"] for a in out["allocation"]}
    if (
        ref.structural(doc, by_id, alloc)
        or not ref.check(doc, scenarios[decision], by_id, alloc).ok
    ):
        bad.add("C5 unsound allocation", seed, i, doc, alloc)  # verify(solve(x)) must pass
    stats["actionable"] += 1
    if out["solver_status"] == "OPTIMAL":  # C7
        stats["C7 optimality + canonical tie-break"] += 1
        tiers = {t["name"]: t["value"] for t in out["tiers"]}
        want = {name: exp.tiers[name] for name, _ in ref.TIERS[doc["options"]["profile"]]}
        if tiers != want:
            bad.add("C7 tier values", seed, i, doc, [tiers, want])
        if alloc != exp.allocation:
            bad.add("C7 canonical allocation", seed, i, doc, [alloc, exp.allocation])
            return
    if status != exp.status or set(out["failing_scenarios"]) != exp.failing:  # C8
        bad.add("C8 status", seed, i, doc, [status, out["failing_scenarios"], sorted(exp.failing)])
    for sid, chk in exp.checks.items():  # C9
        eng = out["verification"]["checks"][sid]
        breaches = sorted((b["on"], b["cash_account_id"], b["balance"]) for b in eng["breaches"])
        globals_ = [(g["on"], g["total"]) for g in eng["global_breaches"]]
        if (eng["ok"], eng["min_balance_by_account"], breaches, globals_) != (
            chk.ok,
            chk.min_balance,
            chk.breaches,
            chk.global_breaches,
        ):
            bad.add("C9 scenario check", seed, i, doc, [sid, eng, chk])
    for line in out["allocation"]:
        c, x = by_id[line["card_id"]], line["amount_minor"]
        want_line = {
            "fee_minor": ref.fee_of(c, x),
            "verified_benefit_minor": ref.ben_of(c, x),
            "potential_benefit_minor": ref.pot_of(c, x),
            "repay_on": c.repay_on.isoformat(),
            "buffer_days": c.buffer,
        }
        if {k: line[k] for k in want_line} != want_line:
            bad.add("C9 allocation line", seed, i, doc, [line, want_line])
    if sensitivity:
        for sid in out["failing_scenarios"]:
            if sid in out["sensitivity"] and "note" not in out["sensitivity"][sid]:
                _compare_sensitivity(doc, out, sid, exp, seed, i, bad)


def _compare_sensitivity(
    doc: Doc,
    out: Doc,
    sid: str,
    exp: Any,  # noqa: ANN401 -- diff_reference.Expected (module loaded from its file)
    seed: int,
    i: int,
    bad: Mismatches,
) -> None:
    sc = next(s for s in doc["scenarios"] if s["scenario_id"] == sid)
    got = out["sensitivity"][sid]
    bad.stats["C13 sensitivity"] += 1
    want_extra = ref.min_extra_cash(doc, sc, exp.cards)
    if {k: got["min_extra_confirmed_cash"].get(k) for k in want_extra} != want_extra:
        bad.add(
            "C13 min extra cash", seed, i, doc, [sid, got["min_extra_confirmed_cash"], want_extra]
        )
    want_max = ref.max_affordable(doc, sc, exp.cards)
    if {k: got["max_affordable_amount"].get(k) for k in want_max} != want_max:
        bad.add("C13 max affordable", seed, i, doc, [sid, got["max_affordable_amount"], want_max])
    want_shift = ref.date_shift(doc, sc)
    if got["first_feasible_date_shift"] != want_shift:
        bad.add("C13 date shift", seed, i, doc, [sid, got["first_feasible_date_shift"], want_shift])


def _compare_verifier(doc: Doc, rng: random.Random, seed: int, j: int, bad: Mismatches) -> None:
    """C11: a random allocation through the solver-free verifier."""
    if ref.data_issues(doc):
        return
    cards = ref.cards_at(doc, ref.day(doc["request"]["txn_date"]))
    by_id = {c.id: c for c in cards}
    ids = [c["card_id"] for c in doc["cards"]] + ["Z"]
    alloc: dict[str, int] = {}
    for cid in rng.sample(ids, k=rng.randint(1, min(3, len(ids)))):
        alloc[cid] = rng.randint(1, 20)
    if rng.random() < 0.5:  # make conservation hold sometimes
        first = next(iter(alloc))
        alloc[first] = max(1, alloc[first] + doc["request"]["amount_minor"] - sum(alloc.values()))
    decision = doc["options"]["decision_scenario"]
    res = verify_from_protocol(
        doc, [{"card_id": k, "amount_minor": v} for k, v in alloc.items()], decision
    )
    bad.stats["C11 random allocations"] += 1
    errors = runner.schema_errors(
        REGISTRY, "PlanOutcome.schema.json#/$defs/VerificationResult", res
    )
    if errors or res.get("data_issues"):
        bad.add("C11 result", seed, j, doc, [errors[:3], res.get("data_issues")])
        return
    ver = res["verification"]
    violations = ref.structural(doc, by_id, alloc)
    known = {k: v for k, v in alloc.items() if k in by_id}
    for sc in doc["scenarios"]:
        chk = ref.check(doc, sc, by_id, known)
        eng = ver["checks"][sc["scenario_id"]]
        breaches = sorted((b["on"], b["cash_account_id"], b["balance"]) for b in eng["breaches"])
        if (eng["ok"], eng["min_balance_by_account"], breaches) != (
            chk.ok,
            chk.min_balance,
            chk.breaches,
        ):
            bad.add("C11 check", seed, j, doc, [alloc, sc["scenario_id"], eng, chk])
        if sc["scenario_id"] == decision:
            want_ok = not violations and chk.ok
    if ver["structural_ok"] != (not violations) or ver["ok"] != want_ok:
        bad.add("C11 structural/ok", seed, j, doc, [alloc, ver["violations"], violations])


def test_engine_matches_the_independent_reference_r3e_06_r3e_16() -> None:
    """R3E-06/R3E-16: verify(solve(x)) always passes, the verifier agrees with the reference on
    random allocations, the optimum and its canonical tie-break are the reference's, and every
    outcome is the same with 1 and with 8 workers. Seeds are fixed (see SEEDS)."""
    bad = Mismatches()
    started = time.monotonic()
    for seed in SEEDS:
        rng = random.Random(seed)  # noqa: S311 -- seeded test data, not cryptography
        for i in range(PER_SEED):
            doc = ref.gen_doc(rng)
            try:
                inputs_from_protocol(doc)
            except ProtocolError as e:  # the generator must produce valid documents
                bad.add("C1 generator", seed, i, doc, str(e))
                continue
            _compare_instance(
                doc,
                seed,
                i,
                bad,
                sensitivity=i % SENSITIVITY_EVERY == 0,
                determinism=i % DETERMINISM_EVERY == 0,
            )
        for j in range(PER_SEED):
            _compare_verifier(ref.gen_doc(rng), rng, seed, j, bad)
    elapsed = time.monotonic() - started
    summary = {
        "seeds": SEEDS,
        "instances_per_seed": PER_SEED,
        "fuzz": FUZZ,
        "elapsed_s": round(elapsed, 1),
        "stats": dict(sorted(bad.stats.items())),
    }
    sys.stdout.write(f"\ndifferential summary: {json.dumps(summary, ensure_ascii=False)}\n")
    assert bad.found == [], json.dumps(bad.found[:2], ensure_ascii=False, default=str)[:6000]
    assert bad.stats["actionable"] > 0
    assert bad.stats["C7 optimality + canonical tie-break"] > 0
    assert bad.stats["infeasible (proved)"] > 0
    assert bad.stats["C13 sensitivity"] > 0


# The two instances on which the wave-3 review saw a SENSITIVITY allocation change between runs
# (review §4.6: seed 105 #10, max_affordable_amount; seed 203 #200 with timestamps,
# min_extra_confirmed_cash). Regenerated with the review's own generator. Under model 1.1.0 the
# second one is no longer INFEASIBLE: its baseline breaches the global floor of 0.20 on
# 2026-11-14 (total 0.01), which is now BASELINE_SHORTFALL (§12.8) -- and with horizon_end five
# days after the purchase every card would repay after it (§12.7). Both still have to give one
# outcome for any workers, equal to the reference's.
REVIEW_INSTANCES = [
    (105, 10, 0.25, "INFEASIBLE"),
    (203, 200, 1.0, "BASELINE_SHORTFALL"),
]


@pytest.mark.parametrize(
    ("seed", "index", "ts_rate", "status"), REVIEW_INSTANCES, ids=["105-10", "203-200"]
)
def test_review_nondeterministic_sensitivity_is_reproducible_r3e_06(
    seed: int, index: int, ts_rate: float, status: str
) -> None:
    """R3E-06: the review's nondeterministic sensitivity instances now give one outcome, with 8
    and with 1 worker, equal to the reference's (canonical sensitivity allocations included)."""
    rng = random.Random(seed)  # noqa: S311 -- seeded test data, not cryptography
    doc = [ref.gen_review_doc(rng, timestamp_rate=ts_rate) for _ in range(index + 1)][index]
    outcomes = set()
    for workers in (8, 8, 8, 8, 8, 1, 1):
        d = copy.deepcopy(doc)
        d["options"]["workers"] = workers
        outcomes.add(stable(plan_from_protocol(d)))
    assert len(outcomes) == 1
    out = json.loads(outcomes.pop())
    exp = ref.expected(doc)
    assert out["business_status"] == exp.status == status
    if status != "INFEASIBLE":
        return
    decision = doc["options"]["decision_scenario"]
    sc = next(s for s in doc["scenarios"] if s["scenario_id"] == decision)
    sens = out["sensitivity"][decision]
    want_extra = ref.min_extra_cash(doc, sc, exp.cards)
    assert {k: sens["min_extra_confirmed_cash"][k] for k in want_extra} == want_extra
    want_max = ref.max_affordable(doc, sc, exp.cards)
    assert {k: sens["max_affordable_amount"][k] for k in want_max} == want_max
    assert sens["max_affordable_amount"]["allocation"] == {"D": 4}  # the review saw A or D
