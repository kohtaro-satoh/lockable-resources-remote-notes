### S02: fan-in-contention

#### Sequence

- SEQ01 Configure B remote server and A/C clients
- SEQ02 Trigger holder then waiter

#### Checkpoints

| ID | Step | API / Action | Expected | Actual | Result |
|---|---|---|---|---|---|
| CP01 | Remote setup | Groovy settings | B exposed and A/C linked | configured and verified | PASS |
| CP02 | Job upsert | WorkflowJob upsert | holder/waiter updated | done | PASS |
| CP03 | Build results | Build API | holder/waiter SUCCESS | holder=SUCCESS waiter=SUCCESS | PASS |
| CP04 | Wait evidence | Elapsed time | >= 15s | 33s | PASS |
| CP05 | Waiter marker | ConsoleText | WAITER_ACQUIRED | found | PASS |

#### Artifacts

- holder-console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260615173923-e2e-test/fan-in-contention/holder-console.txt
- waiter-console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260615173923-e2e-test/fan-in-contention/waiter-console.txt
- summary: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260615173923-e2e-test/fan-in-contention/summary.txt
