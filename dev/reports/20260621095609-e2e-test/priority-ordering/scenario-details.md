### S12: priority-ordering

#### Summary

- holder (B local): SUCCESS
- local waiter (B, priority 0, enqueued first): SUCCESS
- remote waiter (A->B, priority 10, enqueued second): SUCCESS
- after holder release the resource was observed remote-locked first: true

#### Checkpoints

| ID | Result |
|---|---|
| CP01 | PASS (all three builds SUCCESS) |
| CP02 | PASS (priority-10 remote entry acquired before priority-0 local waiter) |
| CP03 | PASS (both waiter bodies executed) |
| CP04 | PASS (resource free at end) |

#### Artifacts

- holder console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260621095609-e2e-test/priority-ordering/holder-console.txt
- local waiter console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260621095609-e2e-test/priority-ordering/local-waiter-console.txt
- remote high console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260621095609-e2e-test/priority-ordering/remote-high-console.txt
- summary: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260621095609-e2e-test/priority-ordering/summary.txt
