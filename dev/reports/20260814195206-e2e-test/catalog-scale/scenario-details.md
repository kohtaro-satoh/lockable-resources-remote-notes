### B06: catalog-scale

**Result: PASS** (12 checkpoints, 0 failed)

#### Sequence

- SEQ01 Expose a probe resource on B and link A to it
- SEQ02 Measure the baseline acquire latency on a small catalogue
- SEQ03 Grow the catalogue and measure discovery at each size
- SEQ04 Measure acquire latency while the catalogue is being fetched continuously
- SEQ05 Check the probe resource survived it all

#### Checkpoints

| ID | Step | API / Action | Expected | Actual | Result |
|---|---|---|---|---|---|
| CP01 | Acquire + release, small catalogue | median of 9 cycles | (observed) | 78ms | INFO |
| CP02 | Catalogue of 100 | GET /resources | (observed) | 19ms, 11530 bytes, 100 of 100 listed | INFO |
| CP03 | All 100 resources are listed | GET /resources body | 100 | 100 | PASS |
| CP04 | Catalogue of 500 | GET /resources | (observed) | 32ms, 49530 bytes, 500 of 500 listed | INFO |
| CP05 | All 500 resources are listed | GET /resources body | 500 | 500 | PASS |
| CP06 | Catalogue of 2000 | GET /resources | (observed) | 69ms, 193031 bytes, 2000 of 2000 listed | INFO |
| CP07 | All 2000 resources are listed | GET /resources body | 2000 | 2000 | PASS |
| CP08 | Discovery still answers promptly at 2000 resources | milliseconds for GET /resources | < 15000 | 34 | PASS |
| CP09 | Acquire + release, catalogue of 2000 served by 4 clients in a loop | median of 9 cycles | (observed) | 115ms | INFO |
| CP10 | Latency multiple under discovery load | loaded / baseline | (observed) | 1.47x | INFO |
| CP11 | Acquiring stays responsive while discovery is under load | milliseconds, median | < 5000 | 115 | PASS |
| CP12 | Probe resource free at the end | Groovy resource state on b | free: not locked, no lease, not reserved | free | PASS |

#### Summary

- sizes: 100 500 2000
- baseline_acquire_ms: 78
- loaded_acquire_ms: 115
- latency_multiple: 1.47
- catalog_ms_at_2000: 34
- catalog_bytes_at_2000: 193031

#### Artifacts

- scaling measurements: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260814195206-e2e-test/catalog-scale/catalog-scaling.txt

