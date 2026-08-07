### S15: label-quantity-all

#### Summary

- build result: SUCCESS
- S15RES (combined): s15-pool1-1785888429,s15-pool2-1785888429,s15-pool3-1785888429
- during-body lease (all three): 65b22d43-846e-49fb-88ff-c9601fd0e67d
- after state: s15-pool1-1785888429_FREE=true;s15-pool2-1785888429_FREE=true;s15-pool3-1785888429_FREE=true;Result: [s15-pool1-1785888429, s15-pool2-1785888429, s15-pool3-1785888429]

#### Checkpoints

| ID | Result |
|---|---|
| CP01 | PASS (build SUCCESS) |
| CP02 | PASS (all 3 pool resources locked during body under one lease — "0 = all") |
| CP03 | PASS (S15RES=s15-pool1-1785888429,s15-pool2-1785888429,s15-pool3-1785888429, all three, comma-separated) |
| CP05 | PASS (all three released after completion) |
| CP06 | PASS (Remote lock acquired on found) |

#### Artifacts

- console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260805085716-e2e-test/label-quantity-all/console.txt
- summary: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260805085716-e2e-test/label-quantity-all/summary.txt
