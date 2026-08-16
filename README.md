# Reference material for PR #1077

Supporting material for
[jenkinsci/lockable-resources-plugin#1077](https://github.com/jenkinsci/lockable-resources-plugin/pull/1077),
which closes the required items of
[#1025](https://github.com/jenkinsci/lockable-resources-plugin/issues/1025).

Everything here is about **that branch**: what it was designed to do, what it fixes, and how it was
verified. Background that predates it is linked rather than repeated:

| For | Go to |
|---|---|
| Why the feature exists, use cases, architecture study | [docs/remote-lr-pull-1055](https://github.com/kohtaro-satoh/lockable-resources-remote-notes/tree/docs/remote-lr-pull-1055) |
| The bridge itself (M1 … M1J design specs) | [docs/remote-lr-pull-1055 — dev/docs-e](https://github.com/kohtaro-satoh/lockable-resources-remote-notes/tree/docs/remote-lr-pull-1055/dev/docs-e) |
| The merged PR it follows up | [#1055](https://github.com/jenkinsci/lockable-resources-plugin/pull/1055) |
| The epic and its phases | [#1025](https://github.com/jenkinsci/lockable-resources-plugin/issues/1025) |

---

## Design

- [design_01.md](dev/docs-j/ph1-ms2/design_01.md) (Japanese) — the design this PR implements: the
  client-side view of remote locks, resource discovery, and the operational switches. The English
  mirror follows once its §10 open questions are settled.

## Verification

Commit `bdca858`.

| Suite | Result |
|---|---|
| `mvn verify` | [report](dev/reports/20260814192837-mvn-verify.md) — 463 run / 0 failures / 1 skip, all gates clean |
| E2E | [report](dev/reports/20260814195206-e2e-test.md) — 32/32 (20 function / 4 data / 6 time / 2 scale) |
| Load `stress` | [report](dev/reports/20260814122345-load-test-stress.md) — 190 SUCCESS / 10 clean `LOCK_WAIT_TIMEOUT`, overlaps 0, HUNG 0 |
| Load `timeout-race` | [report](dev/reports/20260814123643-load-test-timeout-race.md) — 92 SUCCESS / 108 clean `LOCK_WAIT_TIMEOUT`, overlaps 0, HUNG 0 |

The two load presets ask different questions. `stress` is about contention and throughput;
`timeout-race` puts the deadlines *inside* the window, so the code that runs when an allocate
timeout expires is exercised in bulk rather than a handful of times. Its failure count is the point
of the preset, not a regression.

Mutual exclusion is judged from the servers' own audit trail rather than from what the clients
believed they held: a build logs its acquisition after taking the lock and its release before giving
it up, so its interval lies inside the true one and can miss a real overlap. Both counts are in the
reports.

### Coverage

How much of the remote code each layer actually reaches, measured by attaching the JaCoCo agent to
the controllers — not inferred.

| Layer | Line | Branch |
|---|---|---|
| Unit (`mvn verify`) | 88.4% | 72.5% |
| [E2E](dev/reports/20260815163329-coverage-e2e.md) | 82.7% | 63.6% |
| [Load](dev/reports/20260815165743-coverage-load-stress.md) | 54.4% | 34.4% |
| **[All three](dev/reports/20260815172350-coverage-union.md)** | **93.2%** | **80.8%** |

The union is higher than any single layer, so E2E and load do reach ground the unit tests do not.
What remains is 88 lines and 105 branches that nothing reaches — the shape of gap that two of this
PR's fixes were sitting in.

### UI

- [ui-capture](dev/reports/20260814114953-ui-capture.md) — the same states photographed on upstream
  and on this branch, because a tab, a badge and a banner are not reviewable from a diff. The
  screenshots linked from the PR are in [dev/pr-assets/ph1-ms2-ui/](dev/pr-assets/ph1-ms2-ui/)

## Test specifications

- [E2E](dev/docs-e/E2E_TEST_SPECIFICATION.md) ([j](dev/docs-j/E2E_TEST_SPECIFICATION.md)) — 32
  scenarios, each tagged with the axis it covers
- [Load](dev/docs-e/LOAD_TEST_SPECIFICATION.md) ([j](dev/docs-j/LOAD_TEST_SPECIFICATION.md)) — the
  separate suite that drives the remote lock at production scale
- [BOUNDARY_COVERAGE_ANALYSIS](dev/docs-j/BOUNDARY_COVERAGE_ANALYSIS.md) (Japanese) — what the E2E
  suite covers on the data / time / scale axes and what it does not. This is how the allocate-timeout
  defect was found

## Test environment

| Path | Content |
|---|---|
| [dev/jenkins-env/](dev/jenkins-env/) | Four-controller Docker environment — `start.sh`, `run-e2e.sh`, `run-load.sh`, `scenarios/`. See its [README](dev/jenkins-env/README.md) |
| [dev/jenkins-env/capture/](dev/jenkins-env/capture/) | Scripted browser that photographs the UI; both plugin versions go through the same script |
| [dev/jenkins-env/coverage/](dev/jenkins-env/coverage/) | JaCoCo agent wiring, per-layer collection, and the union report. Off by default |
| [dev/run-mvn-verify.sh](dev/run-mvn-verify.sh) | CI-equivalent `mvn clean verify` (isolated worktree build, all static gates) |

---

Working files — per-cycle implementation steps, result and review logs, drafts — stay on the
development branch.
