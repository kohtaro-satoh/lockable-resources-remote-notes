### S15: label-quantity-all

#### Summary

- build result: SUCCESS
- S15RES (combined): s15-pool1-1781513372,s15-pool2-1781513372,s15-pool3-1781513372
- during-body lease (all three): f7b0afe4-0a1c-45eb-94fb-857047fec37b
- after state: s15-pool1-1781513372_FREE=true;s15-pool2-1781513372_FREE=true;s15-pool3-1781513372_FREE=true;Result: [s15-pool1-1781513372, s15-pool2-1781513372, s15-pool3-1781513372]

#### Checkpoints

| ID | Result |
|---|---|
| CP01 | PASS (build SUCCESS) |
| CP02 | PASS (all 3 pool resources locked during body under one lease — "0 = all") |
| CP03 | PASS (S15RES=s15-pool1-1781513372,s15-pool2-1781513372,s15-pool3-1781513372, all three, comma-separated) |
| CP05 | PASS (all three released after completion) |
| CP06 | PASS (Remote lock acquired on found) |

#### Artifacts

- console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260615173923-e2e-test/label-quantity-all/console.txt
- summary: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260615173923-e2e-test/label-quantity-all/summary.txt
