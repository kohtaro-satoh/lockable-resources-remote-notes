### S15: label-quantity-all

#### Summary

- build result: SUCCESS
- S15RES (combined): s15-pool1-1785027314,s15-pool2-1785027314,s15-pool3-1785027314
- during-body lease (all three): 893493a1-fc1f-4902-a6d0-7959671a27dc
- after state: s15-pool1-1785027314_FREE=true;s15-pool2-1785027314_FREE=true;s15-pool3-1785027314_FREE=true;Result: [s15-pool1-1785027314, s15-pool2-1785027314, s15-pool3-1785027314]

#### Checkpoints

| ID | Result |
|---|---|
| CP01 | PASS (build SUCCESS) |
| CP02 | PASS (all 3 pool resources locked during body under one lease — "0 = all") |
| CP03 | PASS (S15RES=s15-pool1-1785027314,s15-pool2-1785027314,s15-pool3-1785027314, all three, comma-separated) |
| CP05 | PASS (all three released after completion) |
| CP06 | PASS (Remote lock acquired on found) |

#### Artifacts

- console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260726094517-e2e-test/label-quantity-all/console.txt
- summary: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260726094517-e2e-test/label-quantity-all/summary.txt
