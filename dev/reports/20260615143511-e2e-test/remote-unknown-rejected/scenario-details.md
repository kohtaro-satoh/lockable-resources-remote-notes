### S17: remote-unknown-rejected

#### Summary

- build result: FAILURE (expected FAILURE — fast 404 rejection, not a hang)
- unknown resource: s17-unknown-1781502356
- ephemeral created on server: no

#### Checkpoints

| ID | Result |
|---|---|
| CP01 | PASS (build FAILURE — unknown acquire rejected fast, not queued) |
| CP02 | PASS (console shows HTTP 404 / UNKNOWN_RESOURCE) |
| CP03 | PASS (lock body did not run) |
| CP04 | PASS (server created no ephemeral resource for the unknown name — H-1) |

#### Artifacts

- console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260615143511-e2e-test/remote-unknown-rejected/console.txt
- summary: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260615143511-e2e-test/remote-unknown-rejected/summary.txt
