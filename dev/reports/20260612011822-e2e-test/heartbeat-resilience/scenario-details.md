### S11: heartbeat-resilience

#### Summary

- build result: SUCCESS
- heartbeat warnings observed on A: 4
- B resource state: FREE=true

#### Checkpoints

| ID | Result |
|---|---|
| CP01 | PASS (build SUCCESS despite heartbeat failures) |
| CP02 | PASS (body ran to completion) |
| CP03 | PASS (4 heartbeat-failure warnings on A) |
| CP04 | PASS (B resource released after completion) |

#### Artifacts

- console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260612011822-e2e-test/heartbeat-resilience/console.txt
- heartbeat warnings: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260612011822-e2e-test/heartbeat-resilience/heartbeat-warnings.txt
- summary: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260612011822-e2e-test/heartbeat-resilience/summary.txt
