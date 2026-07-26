### S14: extra-label-resources

#### Summary

- build result: SUCCESS
- S14RES (combined): s14-res1-1785027292,s14-gpu-1785027292
- during-body lease (r1/gpu): ab40550e-956a-49d0-a661-ae5659210279 / ab40550e-956a-49d0-a661-ae5659210279
- after state: R1_FREE=true;GPU_FREE=true

#### Checkpoints

| ID | Result |
|---|---|
| CP01 | PASS (build SUCCESS) |
| CP02 | PASS (main + label-based extra locked during body by same lease — atomic, C-1) |
| CP03 | PASS (S14RES=s14-res1-1785027292,s14-gpu-1785027292, comma-separated) |
| CP04 | PASS (S14RES0/S14RES1 present) |
| CP05 | PASS (both released after completion) |
| CP06 | PASS (Remote lock acquired on found) |

#### Artifacts

- console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260726094517-e2e-test/extra-label-resources/console.txt
- summary: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260726094517-e2e-test/extra-label-resources/summary.txt
