#!/usr/bin/env python3
"""Turn a jacoco.csv into the report we actually read.

The HTML report answers "what did this run touch". The question worth asking is narrower: how much
of the *remote* code does a suite reach, and which classes does it not reach at all. A class at 0%
after an E2E run is the interesting row - it means the only thing exercising it is the unit tests,
which is exactly the blind spot that hid A6 and A7.
"""

import csv
import sys
from collections import OrderedDict

REMOTE_MARKERS = ("remote", "Remote")


def pct(covered: int, missed: int) -> float:
    total = covered + missed
    return 100.0 * covered / total if total else 0.0


def is_remote(package: str, cls: str) -> bool:
    """Remote-related = in the remote package, or a class whose name says so."""
    return package.endswith(".remote") or any(m in cls for m in REMOTE_MARKERS)


def main() -> None:
    csv_path, label, sha = sys.argv[1], sys.argv[2], sys.argv[3]

    rows = []
    with open(csv_path, newline="", encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            rows.append(
                {
                    "package": r["PACKAGE"],
                    "class": r["CLASS"],
                    "lc": int(r["LINE_COVERED"]),
                    "lm": int(r["LINE_MISSED"]),
                    "bc": int(r["BRANCH_COVERED"]),
                    "bm": int(r["BRANCH_MISSED"]),
                }
            )

    remote = [r for r in rows if is_remote(r["package"], r["class"])]

    def totals(rs):
        return (
            sum(r["lc"] for r in rs),
            sum(r["lm"] for r in rs),
            sum(r["bc"] for r in rs),
            sum(r["bm"] for r in rs),
        )

    alc, alm, abc, abm = totals(rows)
    rlc, rlm, rbc, rbm = totals(remote)

    out = []
    w = out.append
    w(f"# Coverage — {label}\n")
    w(f"- plugin: `{sha}`")
    w(f"- source: `{csv_path}`")
    w("- measured by attaching the JaCoCo agent to the four controllers, so this is what the suite")
    w("  drives through a running Jenkins — not what the unit tests reach.\n")

    w("## Totals\n")
    w("| Scope | Line | Branch |")
    w("|---|---|---|")
    w(f"| remote-related | {pct(rlc, rlm):.1f}% ({rlc}/{rlc + rlm}) | {pct(rbc, rbm):.1f}% ({rbc}/{rbc + rbm}) |")
    w(f"| whole plugin | {pct(alc, alm):.1f}% ({alc}/{alc + alm}) | {pct(abc, abm):.1f}% ({abc}/{abc + abm}) |")
    w("")

    untouched = sorted(
        (r for r in remote if r["lc"] == 0 and r["lm"] > 0),
        key=lambda r: -r["lm"],
    )
    w("## Remote classes this suite never entered\n")
    if not untouched:
        w("None — every remote class was reached.\n")
    else:
        w("Nothing here is necessarily wrong: some of it is only reachable from a unit test by")
        w("design. It is the list to read before assuming a suite covers something.\n")
        w("| Class | Lines missed |")
        w("|---|---|")
        for r in untouched:
            w(f"| `{r['package'].split('.')[-1]}.{r['class'].split('.')[-1]}` | {r['lm']} |")
        w("")

    partial = sorted(
        (r for r in remote if r["lc"] > 0 and r["lm"] > 0),
        key=lambda r: -r["lm"],
    )[:15]
    if partial:
        w("## Remote classes with the most unreached lines\n")
        w("| Class | Line | Branch | Lines missed |")
        w("|---|---|---|---|")
        for r in partial:
            name = f"{r['package'].split('.')[-1]}.{r['class'].split('.')[-1]}"
            w(f"| `{name}` | {pct(r['lc'], r['lm']):.1f}% | {pct(r['bc'], r['bm']):.1f}% | {r['lm']} |")
        w("")

    print("\n".join(out))


if __name__ == "__main__":
    main()
