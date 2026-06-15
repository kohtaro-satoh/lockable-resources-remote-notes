### S16: remote-resource-properties

#### Summary

- build result: SUCCESS
- property value: 10.9.8.14
- S16RES0_S16_IP (bridged): 10.9.8.14
- after state: FREE=true

#### Checkpoints

| ID | Result |
|---|---|
| CP01 | PASS (build SUCCESS) |
| CP02 | PASS (S16RES / S16RES0 == s16-board-1781481414) |
| CP03 | PASS (resource-property env var S16RES0_S16_IP=10.9.8.14 bridged — M1D) |
| CP04 | PASS (Remote lock acquired on found) |
| CP05 | PASS (resource released after completion) |

#### Artifacts

- console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260615084634-e2e-test/remote-resource-properties/console.txt
- summary: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260615084634-e2e-test/remote-resource-properties/summary.txt
