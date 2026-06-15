### S15: label-quantity-all

#### Summary

- build result: SUCCESS
- S15RES (combined): s15-pool1-1781502325,s15-pool2-1781502325,s15-pool3-1781502325
- during-body lease (all three): d97504ff-04cf-4e6e-96b8-c5d73e98e73f
- after state: s15-pool1-1781502325_FREE=true;s15-pool2-1781502325_FREE=true;s15-pool3-1781502325_FREE=true;Result: [s15-pool1-1781502325, s15-pool2-1781502325, s15-pool3-1781502325]

#### Checkpoints

| ID | Result |
|---|---|
| CP01 | PASS (build SUCCESS) |
| CP02 | PASS (all 3 pool resources locked during body under one lease — "0 = all") |
| CP03 | PASS (S15RES=s15-pool1-1781502325,s15-pool2-1781502325,s15-pool3-1781502325, all three, comma-separated) |
| CP05 | PASS (all three released after completion) |
| CP06 | PASS (Remote lock acquired on found) |

#### Artifacts

- console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260615143511-e2e-test/label-quantity-all/console.txt
- summary: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260615143511-e2e-test/label-quantity-all/summary.txt
