### S13: stale-admin-release

#### Summary

- ghost lease: lockId=3ef00e53-f230-4684-9bdd-6f7e17859ee2 (no heartbeats sent)
- STALE reached after: ~50s
- waiter result: SUCCESS

#### Checkpoints

| ID | Result |
|---|---|
| CP01 | PASS (ghost acquire ACQUIRED) |
| CP02 | PASS (record STALE after ~50s without heartbeats) |
| CP03 | PASS (resource still held while STALE — fail-close) |
| CP04 | PASS (admin releaseRemoteLock succeeded) |
| CP05 | PASS (local waiter woke and completed) |
| CP06 | PASS (resource free at end) |

#### Artifacts

- waiter console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260612011822-e2e-test/stale-admin-release/waiter-console.txt
- summary: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260612011822-e2e-test/stale-admin-release/summary.txt
