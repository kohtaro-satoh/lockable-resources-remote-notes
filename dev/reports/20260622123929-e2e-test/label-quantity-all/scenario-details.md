### S15: label-quantity-all

#### Summary

- build result: SUCCESS
- S15RES (combined): s15-pool1-1782100120,s15-pool2-1782100120,s15-pool3-1782100120
- during-body lease (all three): 69c87dc7-ac1c-44bf-af24-dfe735577b76
- after state: s15-pool1-1782100120_FREE=true;s15-pool2-1782100120_FREE=true;s15-pool3-1782100120_FREE=true;Result: [s15-pool1-1782100120, s15-pool2-1782100120, s15-pool3-1782100120]

#### Checkpoints

| ID | Result |
|---|---|
| CP01 | PASS (build SUCCESS) |
| CP02 | PASS (all 3 pool resources locked during body under one lease — "0 = all") |
| CP03 | PASS (S15RES=s15-pool1-1782100120,s15-pool2-1782100120,s15-pool3-1782100120, all three, comma-separated) |
| CP05 | PASS (all three released after completion) |
| CP06 | PASS (Remote lock acquired on found) |

#### Artifacts

- console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260622123929-e2e-test/label-quantity-all/console.txt
- summary: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260622123929-e2e-test/label-quantity-all/summary.txt
