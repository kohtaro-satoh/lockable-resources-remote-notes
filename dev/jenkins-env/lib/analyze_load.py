#!/usr/bin/env python3
"""Analyze grid-storm load events (LLT lines) -> metrics, overlaps, classification, report.

See dev/docs-j/LOAD_TEST_SPECIFICATION.md. Pure stdlib; matplotlib is optional
(plots are generated only if it is importable).
"""
import argparse
import csv
import json
import os
import re
from collections import defaultdict

_UNITS = {"B": 1, "kB": 1e3, "KB": 1e3, "MB": 1e6, "GB": 1e9, "TB": 1e12,
          "KiB": 1024, "MiB": 1024**2, "GiB": 1024**3, "TiB": 1024**4}


def parse_size(s):
    m = re.match(r"\s*([0-9.]+)\s*([A-Za-z]+)", s or "")
    if not m:
        return 0.0
    return float(m.group(1)) * _UNITS.get(m.group(2), 1.0)


def load_netstats(path):
    """docker stats samples -> {container: [(epochMs, cpu%, memBytes, rxBytes, txBytes)]} (cumulative net)."""
    if not path or not os.path.exists(path):
        return None
    series = defaultdict(list)
    with open(path, newline="") as f:
        for row in csv.DictReader(f):
            try:
                ts = int(row["epochMs"])
            except (ValueError, KeyError):
                continue
            cpu = float((row.get("cpu") or "0").replace("%", "").strip() or 0)
            mem = parse_size((row.get("mem") or "").split("/")[0])
            net = row.get("net") or ""
            rx, tx = (net.split("/") + ["", ""])[:2]
            series[row["name"]].append((ts, cpu, mem, parse_size(rx), parse_size(tx)))
    for k in series:
        series[k].sort()
    return series


def summarize_netstats(series):
    """Per-container summary: peak cpu%, peak mem, total net rx/tx delta over the run."""
    out = {}
    for name, rows in series.items():
        if not rows:
            continue
        peak_cpu = max(r[1] for r in rows)
        peak_mem = max(r[2] for r in rows)
        rx_delta = max(0.0, rows[-1][3] - rows[0][3])
        tx_delta = max(0.0, rows[-1][4] - rows[0][4])
        out[name] = {
            "peak_cpu_pct": round(peak_cpu, 1),
            "peak_mem_mib": round(peak_mem / 1024**2, 1),
            "net_rx_total_mb": round(rx_delta / 1e6, 2),
            "net_tx_total_mb": round(tx_delta / 1e6, 2),
            "samples": len(rows),
        }
    return out


def net_throughput_series(rows):
    """cumulative net -> (t_sec_from_start, bytes_per_sec) using consecutive deltas."""
    xs, ys = [], []
    for i in range(1, len(rows)):
        dt = (rows[i][0] - rows[i - 1][0]) / 1000.0
        if dt <= 0:
            continue
        d = (rows[i][3] - rows[i - 1][3]) + (rows[i][4] - rows[i - 1][4])
        xs.append((rows[i][0] - rows[0][0]) / 1000.0)
        ys.append(max(0.0, d) / dt)
    return xs, ys


def classify_failures(consoles_dir):
    """Bucket FAILURE/ABORTED consoles by their failure signature (for the load report)."""
    out = {"LOCK_WAIT_TIMEOUT": 0, "remote_404_comm_failure": 0, "job_timeout_abort": 0, "other": 0}
    if not consoles_dir or not os.path.isdir(consoles_dir):
        return out
    for name in os.listdir(consoles_dir):
        if not name.endswith(".txt"):
            continue
        try:
            with open(os.path.join(consoles_dir, name), errors="replace") as fh:
                txt = fh.read()
        except OSError:
            continue
        if "Finished: FAILURE" not in txt and "Finished: ABORTED" not in txt:
            continue
        if "errorCode=LOCK_WAIT_TIMEOUT" in txt:
            out["LOCK_WAIT_TIMEOUT"] += 1
        elif ("returned HTTP 404" in txt or "communication failure" in txt
              or "server may have restarted" in txt):
            out["remote_404_comm_failure"] += 1
        elif "Finished: ABORTED" in txt or "Timeout has been exceeded" in txt:
            out["job_timeout_abort"] += 1
        else:
            out["other"] += 1
    return out


def pct(sorted_vals, p):
    if not sorted_vals:
        return None
    k = (len(sorted_vals) - 1) * p
    lo = int(k)
    hi = min(lo + 1, len(sorted_vals) - 1)
    frac = k - lo
    return sorted_vals[lo] + (sorted_vals[hi] - sorted_vals[lo]) * frac


def load_events(path):
    rows = []
    with open(path, newline="") as f:
        r = csv.DictReader(f)
        for row in r:
            try:
                row["epochMs"] = int(row["epochMs"])
                row["iter"] = int(row["iter"])
            except (ValueError, KeyError):
                continue
            rows.append(row)
    return rows


def load_results(path):
    res = {}  # buildUrl -> (controller, result)
    if not os.path.exists(path):
        return res
    with open(path, newline="") as f:
        for row in csv.DictReader(f):
            res[row["buildUrl"]] = (row["controller"], row["result"])
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--events", required=True)
    ap.add_argument("--results", required=True)
    ap.add_argument("--netstats", default="")
    ap.add_argument("--capacity-exposed", type=int, default=40)
    ap.add_argument("--out-metrics", required=True)
    ap.add_argument("--out-overlaps", required=True)
    ap.add_argument("--out-classification", required=True)
    ap.add_argument("--report", required=True)
    ap.add_argument("--run-id", default="")
    ap.add_argument("--preset", default="")
    ap.add_argument("--jobs-per-controller", type=int, default=0)
    ap.add_argument("--iter", type=int, default=0)
    ap.add_argument("--sleep", type=int, default=0)
    ap.add_argument("--remote-timeout", type=int, default=0)
    ap.add_argument("--local-timeout", type=int, default=0)
    ap.add_argument("--job-timeout", type=int, default=0)
    ap.add_argument("--loopback", default="false")
    ap.add_argument("--plugin-commit", default="")
    args = ap.parse_args()

    events = load_events(args.events)
    results = load_results(args.results)
    fail_breakdown = classify_failures(os.path.join(os.path.dirname(args.out_metrics), "consoles"))
    netstats = load_netstats(args.netstats)
    net_summary = summarize_netstats(netstats) if netstats else {}
    plots_dir = os.path.join(os.path.dirname(args.out_metrics), "plots")

    # group events per (jobUid, iter, phase)
    by_key = defaultdict(dict)  # (uid,iter,phase) -> {event: row}
    jobs = defaultdict(list)    # uid -> rows
    for e in events:
        by_key[(e["jobUid"], e["iter"], e["phase"])][e["event"]] = e
        jobs[e["jobUid"]].append(e)

    # queue waits (ms) for REMOTE_MAIN and LOCAL
    queue_waits = []          # (acquire_ms, wait_ms, phase, target)
    hold_intervals = []       # (target, resource, start_ms, end_ms, uid, phase)
    for (uid, it, phase), evs in by_key.items():
        req = evs.get("REQUEST")
        acq = evs.get("ACQUIRED")
        rel = evs.get("RELEASED")
        if req and acq:
            queue_waits.append((acq["epochMs"], acq["epochMs"] - req["epochMs"], phase, acq["target"]))
        if acq and rel:
            names = [n for n in (acq.get("resources") or "").split(";") if n]
            for nm in names:
                hold_intervals.append((acq["target"], nm, acq["epochMs"], rel["epochMs"], uid, phase))

    # overlap detection: per (target,resource), capacity 1
    overlaps = []
    by_res = defaultdict(list)
    for tgt, nm, s, e, uid, phase in hold_intervals:
        by_res[(tgt, nm)].append((s, e, uid, phase))
    for (tgt, nm), ivs in by_res.items():
        ivs.sort()
        for i in range(len(ivs) - 1):
            s1, e1, u1, p1 = ivs[i]
            s2, e2, u2, p2 = ivs[i + 1]
            if e1 > s2:  # overlap
                overlaps.append({
                    "target": tgt, "resource": nm,
                    "a": {"uid": u1, "phase": p1, "start": s1, "end": e1},
                    "b": {"uid": u2, "phase": p2, "start": s2, "end": e2},
                    "overlap_ms": e1 - s2,
                })

    # job classification
    # map uid -> result via results (buildUrl basename not directly uid); fall back to events
    result_by_ctrl_count = defaultdict(int)
    outcomes = {}  # uid -> outcome
    # Build a result lookup by controller is ambiguous; we infer from event completeness + results values.
    res_values = list(results.values())
    for v in res_values:
        result_by_ctrl_count[v[1]] += 1

    # Per-job outcome from its own events + whether a matching build result exists.
    # We can't map uid->buildUrl reliably here, so classify by event completeness and
    # cross-check aggregate result counts in the report.
    for uid, evs in jobs.items():
        iters_done = sum(1 for (u, it, ph), d in by_key.items()
                         if u == uid and ph == "REMOTE_MAIN" and "RELEASED" in d)
        last = max(evs, key=lambda r: r["epochMs"])
        if iters_done >= args.iter and args.iter > 0:
            outcomes[uid] = "COMPLETED"
        elif last["event"] == "REQUEST":
            outcomes[uid] = "TIMED_OUT_or_FAILED"  # refined with build result below
        else:
            outcomes[uid] = "PARTIAL"

    # aggregate result-string counts (authoritative for SUCCESS/FAILURE/ABORTED/UNKNOWN)
    rcount = defaultdict(int)
    for _, r in res_values:
        rcount[r] += 1
    hung = rcount.get("UNKNOWN", 0)

    waits_ms = sorted(w for _, w, _, _ in queue_waits)
    metrics = {
        "runId": args.run_id,
        "preset": args.preset,
        "jobsPerController": args.jobs_per_controller,
        "iter": args.iter,
        "builds_total": len(results),
        "result_counts": dict(rcount),
        "hung": hung,
        "jobs_with_events": len(jobs),
        "queue_wait_ms": {
            "count": len(waits_ms),
            "p50": pct(waits_ms, 0.50),
            "p95": pct(waits_ms, 0.95),
            "p99": pct(waits_ms, 0.99),
            "max": waits_ms[-1] if waits_ms else None,
        },
        "hold_intervals": len(hold_intervals),
        "overlap_violations": len(overlaps),
        "completed_jobs": sum(1 for o in outcomes.values() if o == "COMPLETED"),
        "netstats": net_summary,
        "failure_breakdown": fail_breakdown,
    }

    with open(args.out_metrics, "w") as f:
        json.dump(metrics, f, indent=2)

    with open(args.out_overlaps, "w") as f:
        if not overlaps:
            f.write("")  # empty = no violation
        else:
            for o in overlaps:
                f.write(json.dumps(o) + "\n")

    with open(args.out_classification, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["jobUid", "outcome", "iters_completed_remote_main"])
        for uid in sorted(jobs):
            iters_done = sum(1 for (u, it, ph), d in by_key.items()
                             if u == uid and ph == "REMOTE_MAIN" and "RELEASED" in d)
            w.writerow([uid, outcomes.get(uid, "PARTIAL"), iters_done])

    # optional plots
    plot_links = []
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        os.makedirs(plots_dir, exist_ok=True)

        # queue-wait scatter
        if queue_waits:
            t0 = min(a for a, _, _, _ in queue_waits)
            xs = [(a - t0) / 1000.0 for a, _, _, _ in queue_waits]
            ys = [w / 1000.0 for _, w, _, _ in queue_waits]
            plt.figure(figsize=(9, 4))
            plt.scatter(xs, ys, s=8, alpha=0.5)
            plt.xlabel("acquire time (s from start)")
            plt.ylabel("queue wait (s)")
            plt.title("Queue wait per acquisition")
            plt.tight_layout()
            p = os.path.join(plots_dir, "queue-wait-scatter.png")
            plt.savefig(p, dpi=100); plt.close()
            plot_links.append(("queue-wait-scatter", p))

        # waiters over time (count of REQUEST not yet ACQUIRED)
        ev_pts = []
        for (uid, it, ph), evs in by_key.items():
            req = evs.get("REQUEST"); acq = evs.get("ACQUIRED")
            if req:
                ev_pts.append((req["epochMs"], +1))
                if acq:
                    ev_pts.append((acq["epochMs"], -1))
        if ev_pts:
            ev_pts.sort()
            t0 = ev_pts[0][0]
            xs = []; ys = []; cur = 0
            for ms, d in ev_pts:
                cur += d
                xs.append((ms - t0) / 1000.0); ys.append(cur)
            plt.figure(figsize=(9, 4))
            plt.step(xs, ys, where="post")
            plt.xlabel("time (s from start)")
            plt.ylabel("waiters (REQUEST not yet ACQUIRED)")
            plt.title("Queued waiters over time")
            plt.tight_layout()
            p = os.path.join(plots_dir, "queue-waiters-over-time.png")
            plt.savefig(p, dpi=100); plt.close()
            plot_links.append(("queue-waiters-over-time", p))

        # per-resource mean hold scatter
        agg = defaultdict(list)
        for tgt, nm, s, e, uid, phase in hold_intervals:
            agg[(tgt, nm)].append((s, e))
        if agg:
            t0 = min(s for ivs in agg.values() for s, _ in ivs)
            xs = []; ys = []; sizes = []
            for (tgt, nm), ivs in agg.items():
                holds = [(e - s) / 1000.0 for s, e in ivs]
                mid = (sorted(s for s, _ in ivs)[len(ivs)//2] - t0) / 1000.0
                xs.append(mid); ys.append(sum(holds)/len(holds)); sizes.append(8 + 4*len(ivs))
            plt.figure(figsize=(9, 4))
            plt.scatter(xs, ys, s=sizes, alpha=0.5)
            plt.xlabel("median acquire time (s from start)")
            plt.ylabel("mean hold (s)")
            plt.title("Per-resource mean hold time (size = #acquisitions)")
            plt.tight_layout()
            p = os.path.join(plots_dir, "resource-mean-hold-scatter.png")
            plt.savefig(p, dpi=100); plt.close()
            plot_links.append(("resource-mean-hold-scatter", p))

        # network throughput over time (per container)
        if netstats:
            plt.figure(figsize=(9, 4))
            any_net = False
            for name, rows in sorted(netstats.items()):
                xs, ys = net_throughput_series(rows)
                if xs:
                    plt.plot(xs, [v / 1e3 for v in ys], label=name)
                    any_net = True
            if any_net:
                plt.xlabel("time (s from start)"); plt.ylabel("net throughput (kB/s)")
                plt.title("Container network throughput (rx+tx)")
                plt.legend(fontsize=8); plt.tight_layout()
                p = os.path.join(plots_dir, "network-throughput.png")
                plt.savefig(p, dpi=100); plt.close()
                plot_links.append(("network-throughput", p))
            else:
                plt.close()

            # cpu utilization over time
            plt.figure(figsize=(9, 4))
            any_cpu = False
            for name, rows in sorted(netstats.items()):
                if len(rows) >= 2:
                    t0 = rows[0][0]
                    plt.plot([(r[0] - t0) / 1000.0 for r in rows], [r[1] for r in rows], label=name)
                    any_cpu = True
            if any_cpu:
                plt.xlabel("time (s from start)"); plt.ylabel("CPU %")
                plt.title("Container CPU utilization")
                plt.legend(fontsize=8); plt.tight_layout()
                p = os.path.join(plots_dir, "cpu-utilization.png")
                plt.savefig(p, dpi=100); plt.close()
                plot_links.append(("cpu-utilization", p))
            else:
                plt.close()
    except ImportError:
        plot_links = None  # signal "matplotlib missing"

    # report
    rel = os.path.relpath(os.path.dirname(args.out_metrics), os.path.dirname(args.report))
    total_jobs = args.jobs_per_controller * 4
    loopback_on = str(args.loopback).lower() in ("true", "1", "yes", "on")
    target_phrase = ("a randomly chosen controller (self included)" if loopback_on
                     else "a randomly chosen OTHER controller")
    titles = {
        "queue-waiters-over-time": "Queued waiters over time",
        "queue-wait-scatter": "Queue wait per acquisition",
        "resource-mean-hold-scatter": "Per-resource mean hold time",
        "network-throughput": "Container network throughput (REST API load)",
        "cpu-utilization": "Container CPU utilization",
    }
    captions = {
        "queue-waiters-over-time": "Lock requests waiting (REQUESTed but not yet ACQUIRED) at each instant. Peaks = contention.",
        "queue-wait-scatter": "One point per lock acquisition: how long it waited (y) vs when it was acquired (x).",
        "resource-mean-hold-scatter": "One point per resource: mean hold time (y) vs median acquire time (x); point size = number of acquisitions. Shows load skew across the pool.",
        "network-throughput": "Per-container rx+tx throughput over time = load on the remote-lock REST API.",
        "cpu-utilization": "Per-container CPU% over time; busier remote targets spike higher.",
    }
    qw = metrics["queue_wait_ms"]
    with open(args.report, "w") as f:
        f.write("# Load Test Report — grid-storm\n\n")
        f.write(f"- runId: {args.run_id}\n- preset: {args.preset}\n")
        if args.plugin_commit:
            f.write(f"- plugin under test: `{args.plugin_commit}`\n")
        f.write(f"- builds: {len(results)} (jobs with events: {len(jobs)})\n\n")

        # ---- Scenario: what was actually exercised ----
        f.write("## Scenario — what was tested\n\n")
        f.write("**G01 grid-storm**: all 4 controllers (a/b/c/d) act as both lock **server and client**. "
                f"Each controller starts **{args.jobs_per_controller} concurrent pipeline jobs** "
                f"(**{total_jobs} jobs total** across the grid). Each controller defines 50 lockable resources "
                "(label `pool`); 40 are exposed for remote acquisition.\n\n")
        f.write(f"Every job repeats the following **{args.iter} time(s)** (whole-job timeout {args.job_timeout} min):\n\n")
        f.write(f"1. **remote lock** `lock(label:'pool', quantity:2, serverId:<random>)` — 2 exposed resources on "
                f"{target_phrase} (allocate timeout {args.remote_timeout} min)\n")
        f.write("2. **local lock** `lock(label:'pool', quantity:1)` — 1 local resource, nested inside the remote hold "
                f"(allocate timeout {args.local_timeout} min)\n")
        f.write("3. **remote skipIfLocked** `lock(label:'pool', quantity:1, serverId:<random>, skipIfLocked:true)` — "
                "best-effort; success or failure is swallowed (must not fail the job)\n")
        f.write(f"4. **hold** for {args.sleep}s\n")
        f.write("5. **release** the local lock, then the remote lock\n\n")
        f.write("| parameter | value |\n|---|---|\n")
        f.write(f"| jobs / controller | {args.jobs_per_controller} |\n")
        f.write(f"| total concurrent jobs | {total_jobs} |\n")
        f.write(f"| iterations / job | {args.iter} |\n")
        f.write(f"| hold (sleep) | {args.sleep}s |\n")
        f.write(f"| remote-lock allocate timeout | {args.remote_timeout} min |\n")
        f.write(f"| local-lock allocate timeout | {args.local_timeout} min |\n")
        f.write(f"| whole-job timeout | {args.job_timeout} min |\n")
        f.write(f"| loopback (self as remote target) | {'on' if loopback_on else 'off (cross-controller only)'} |\n\n")

        # ---- Result + invariants ----
        f.write("## Result\n\n")
        for k, v in sorted(rcount.items()):
            f.write(f"- build {k}: {v}\n")
        if sum(fail_breakdown.values()):
            f.write("\n**Failure breakdown** (by console signature)\n\n")
            f.write(f"- `LOCK_WAIT_TIMEOUT` (clean allocate timeout, fail-closed): "
                    f"{fail_breakdown['LOCK_WAIT_TIMEOUT']}\n")
            if fail_breakdown["remote_404_comm_failure"]:
                f.write(f"- remote 404 / communication failure: {fail_breakdown['remote_404_comm_failure']} "
                        f"← queued-expiry-poll-404 regression (fixed in M1I / `e231367`)\n")
            if fail_breakdown["job_timeout_abort"]:
                f.write(f"- whole-job timeout (ABORTED): {fail_breakdown['job_timeout_abort']}\n")
            if fail_breakdown["other"]:
                f.write(f"- other: {fail_breakdown['other']}\n")
        f.write("\n**Invariants**\n\n")
        f.write(f"- mutual-exclusion overlap violations (a resource held beyond capacity at any instant): "
                f"**{len(overlaps)}** {'(PASS)' if not overlaps else '(FAIL)'}\n")
        f.write(f"- termination — HUNG / UNKNOWN result (possible deadlock or lost wakeup): "
                f"**{hung}** {'(PASS)' if hung == 0 else '(FAIL — investigate)'}\n\n")

        f.write("## Queue wait (ms)\n\n")
        f.write(f"- count: {qw['count']}  p50: {qw['p50']}  p95: {qw['p95']}  "
                f"p99: {qw['p99']}  max: {qw['max']}\n\n")

        if net_summary:
            f.write("## Resource utilization (docker stats)\n\n")
            f.write("| container | peak CPU% | peak mem (MiB) | net rx (MB) | net tx (MB) | samples |\n")
            f.write("|---|---|---|---|---|---|\n")
            for name in sorted(net_summary):
                s = net_summary[name]
                f.write(f"| {name} | {s['peak_cpu_pct']} | {s['peak_mem_mib']} | "
                        f"{s['net_rx_total_mb']} | {s['net_tx_total_mb']} | {s['samples']} |\n")
            f.write("\n> net rx/tx = cumulative delta over the run.\n\n")

        # ---- Plots: embedded inline (the .md is self-contained) ----
        f.write("## Plots\n\n")
        if plot_links is None:
            f.write("_matplotlib not installed; plots skipped. Create `dev/.venv` and `pip install matplotlib`, then re-run._\n\n")
        elif not plot_links:
            f.write("_no data to plot._\n\n")
        else:
            for name, p in plot_links:
                base = os.path.basename(p)
                f.write(f"### {titles.get(name, name)}\n\n")
                f.write(f"![{name}]({rel}/plots/{base})\n\n")
                if name in captions:
                    f.write(f"{captions[name]}\n\n")

        f.write("## Artifacts\n\n")
        f.write(f"- events: `{rel}/events.csv`\n- classification: `{rel}/job-classification.csv`\n")
        f.write(f"- overlaps: `{rel}/overlaps.txt`\n- metrics: `{rel}/metrics.json`\n")
        f.write(f"- consoles: `{rel}/consoles/`\n")

    # console summary
    print(f"[analyze] builds={len(results)} results={dict(rcount)} hung={hung} "
          f"overlaps={len(overlaps)} queue_wait_p95_ms={qw['p95']} "
          f"plots={'skipped(no matplotlib)' if plot_links is None else len(plot_links)}")


if __name__ == "__main__":
    main()
