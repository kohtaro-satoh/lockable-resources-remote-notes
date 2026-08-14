### S20: client-side-remote-view

**Result: PASS** (7 checkpoints, 0 failed)

#### Sequence

- SEQ01 Expose the resource on B and link A to it
- SEQ02 Hold the remote lock and read the client page mid-hold
- SEQ03 Let the lock go and read the page again

#### Checkpoints

| ID | Step | API / Action | Expected | Actual | Result |
|---|---|---|---|---|---|
| CP01 | The page offers a Remote tab | grep page-holding.html | contains 'data-lr-tab="remote"' | found | PASS |
| CP02 | The held lock is listed by resource name | grep page-holding.html | contains 's20-board-1786705575' | found | PASS |
| CP03 | It is shown as ACQUIRED | grep page-holding.html | contains 'ACQUIRED' | found | PASS |
| CP04 | The page says the remote is the source of truth | grep page-holding.html | contains 'source of truth' | found | PASS |
| CP05 | Holding build result | Build API | SUCCESS | SUCCESS | PASS |
| CP06 | The entry is gone once released | grep page-released.html | does not contain 's20-board-1786705575' | absent | PASS |
| CP07 | Resource released on B | Groovy resource state on b | free: not locked, no lease, not reserved | free | PASS |

#### Summary

- build_url: http://127.0.0.1:8081/jenkins/job/s20-hold/1/
- result: SUCCESS
- resource: s20-board-1786705575

#### Artifacts

- page while holding: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260814195206-e2e-test/client-side-remote-view/page-holding.html
- console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260814195206-e2e-test/client-side-remote-view/console.txt
- page after release: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260814195206-e2e-test/client-side-remote-view/page-released.html

