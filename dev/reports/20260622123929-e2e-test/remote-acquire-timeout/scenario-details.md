### S18: remote-acquire-timeout

#### Summary

- local holder result: SUCCESS
- remote waiter result: FAILURE (expected FAILURE)
- waiter allocate timeout: 130s (> 120s terminal TTL)
- waiter wait seconds: 152

#### Checkpoints

| ID | Check | Expected |
|---|---|---|
| CP01 | local holder result | SUCCESS |
| CP02 | remote waiter result | FAILURE (fail-closed) |
| CP03 | waiter console errorCode | LOCK_WAIT_TIMEOUT (not 404 / communication failure) |
| CP04 | lock body (SHOULD_NOT_RUN) | not executed |
| CP05 | waiter wait | >= 120s (genuine allocate timeout) |

Overall: PASS

#### Artifacts

- local holder console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260622123929-e2e-test/remote-acquire-timeout/local-holder-console.txt
- remote waiter console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260622123929-e2e-test/remote-acquire-timeout/remote-waiter-console.txt
- summary: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260622123929-e2e-test/remote-acquire-timeout/summary.txt
