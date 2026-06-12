### S15: label-quantity-all

#### Summary

- build result: SUCCESS
- S15RES (combined): s15-pool1-1781275791,s15-pool2-1781275791,s15-pool3-1781275791
- during-body lease (all three): f37ff5e8-f411-4013-b777-89cb3cafd93a
- after state: s15-pool1-1781275791_FREE=true;s15-pool2-1781275791_FREE=true;s15-pool3-1781275791_FREE=true;Result: [s15-pool1-1781275791, s15-pool2-1781275791, s15-pool3-1781275791]

#### Checkpoints

| ID | Result |
|---|---|
| CP01 | PASS (build SUCCESS) |
| CP02 | PASS (all 3 pool resources locked during body under one lease — "0 = all") |
| CP03 | PASS (S15RES=s15-pool1-1781275791,s15-pool2-1781275791,s15-pool3-1781275791, all three, comma-separated) |
| CP05 | PASS (all three released after completion) |
| CP06 | PASS (Remote lock acquired on found) |

#### Artifacts

- console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260612233944-e2e-test/label-quantity-all/console.txt
- summary: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260612233944-e2e-test/label-quantity-all/summary.txt
