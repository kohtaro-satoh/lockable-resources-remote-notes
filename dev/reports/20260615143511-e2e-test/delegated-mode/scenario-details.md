### S09: delegated-mode

#### Summary

- s09-delegated result: SUCCESS
- s09-local-fallback result: SUCCESS
- B resource state: EXISTS=true;LOCKED=false

#### Checkpoints

| ID | Result |
|---|---|
| CP01 | PASS (s09-delegated SUCCESS) |
| CP02 | PASS (DELEGATED_ACQUIRED found) |
| CP03 | PASS (Remote lock acquired on found) |
| CP04 | PASS (serverId=b found) |
| CP05 | PASS (s09-local-fallback SUCCESS) |
| CP06 | PASS (LOCAL_ACQUIRED found) |
| CP07 | PASS (Remote lock acquired on absent in fallback) |
| CP08 | PASS (B resource released) |

#### Artifacts

- delegated console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260615143511-e2e-test/delegated-mode/delegated-console.txt
- fallback console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260615143511-e2e-test/delegated-mode/fallback-console.txt
- summary: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260615143511-e2e-test/delegated-mode/summary.txt
