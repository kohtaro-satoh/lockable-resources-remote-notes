### S21: delegated-mode-page

**Result: PASS** (6 checkpoints, 0 failed)

#### Sequence

- SEQ01 B publishes a resource, A has one of its own, and A delegates to B
- SEQ02 Turn delegation off and read the page again

#### Checkpoints

| ID | Step | API / Action | Expected | Actual | Result |
|---|---|---|---|---|---|
| CP01 | The page announces delegated mode | grep page-delegated.html | contains 'Delegated mode' | found | PASS |
| CP02 | Local resources are still listed | grep page-delegated.html | contains 's21-local-1786776435' | found | PASS |
| CP03 | And the page explains why they still matter | grep page-delegated.html | contains 'remain lockable by other controllers' | found | PASS |
| CP04 | The delegated target's resources are shown | grep page-delegated.html | contains 's21-remote-1786776435' | found | PASS |
| CP05 | The badge goes with the setting | grep page-peer.html | does not contain 'Delegated mode' | absent | PASS |
| CP06 | Local resources survive the transition | grep page-peer.html | contains 's21-local-1786776435' | found | PASS |

#### Summary

- local_resource: s21-local-1786776435
- remote_resource: s21-remote-1786776435

#### Artifacts

- page in delegated mode: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260815153215-e2e-test/delegated-mode-page/page-delegated.html
- page after leaving delegated mode: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260815153215-e2e-test/delegated-mode-page/page-peer.html

