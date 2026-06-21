### S15: label-quantity-all

#### Summary

- build result: SUCCESS
- S15RES (combined): s15-pool1-1782003983,s15-pool2-1782003983,s15-pool3-1782003983
- during-body lease (all three): 7ce12edc-81d9-466b-b332-dc464fb19bc7
- after state: s15-pool1-1782003983_FREE=true;s15-pool2-1782003983_FREE=true;s15-pool3-1782003983_FREE=true;Result: [s15-pool1-1782003983, s15-pool2-1782003983, s15-pool3-1782003983]

#### Checkpoints

| ID | Result |
|---|---|
| CP01 | PASS (build SUCCESS) |
| CP02 | PASS (all 3 pool resources locked during body under one lease — "0 = all") |
| CP03 | PASS (S15RES=s15-pool1-1782003983,s15-pool2-1782003983,s15-pool3-1782003983, all three, comma-separated) |
| CP05 | PASS (all three released after completion) |
| CP06 | PASS (Remote lock acquired on found) |

#### Artifacts

- console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260621095609-e2e-test/label-quantity-all/console.txt
- summary: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260621095609-e2e-test/label-quantity-all/summary.txt
