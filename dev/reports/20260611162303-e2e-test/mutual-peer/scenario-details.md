### S01: mutual-peer

#### Sequence

- SEQ01 Configure A/B as remote servers
- SEQ02 Issue API token and configure credentials
- SEQ03 Configure remote clients A->B and B->A
- SEQ04 Trigger A/B jobs

#### Checkpoints

| ID | Step | API / Action | Expected | Actual | Result |
|---|---|---|---|---|---|
| CP01 | Remote server setup | Groovy /scriptText | A/B remote server ready | configured and verified | PASS |
| CP02 | Credentials setup | ApiToken + Credentials upsert | s01 creds exist | created on A/B | PASS |
| CP03 | Remote client setup | Groovy remotes map | A->B and B->A | configured and verified | PASS |
| CP04 | Build results | Build API | A/B SUCCESS | A=SUCCESS B=SUCCESS | PASS |
| CP05 | Acquire markers | ConsoleText | A_ACQUIRED and B_ACQUIRED | both found | PASS |
| CP06 | Parallel execution | Elapsed time | < 60s | 41s | PASS |

#### Artifacts

- a-console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260611162303-e2e-test/mutual-peer/a-console.txt
- b-console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260611162303-e2e-test/mutual-peer/b-console.txt
- summary: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260611162303-e2e-test/mutual-peer/summary.txt
