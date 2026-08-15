### B04: catalog-cache-ttl

**Result: PASS** (7 checkpoints, 0 failed)

#### Sequence

- SEQ01 B publishes one resource; A delegates to B so its page shows B's catalogue
- SEQ02 Warm the cache and confirm the first resource is visible
- SEQ03 Add a resource on B and read the page immediately (inside the 10s TTL)
- SEQ04 Wait past the TTL and read again
- SEQ05 Stop the server and check the page still renders from what it last knew
- SEQ06 Bring the server back and check the view recovers

#### Checkpoints

| ID | Step | API / Action | Expected | Actual | Result |
|---|---|---|---|---|---|
| CP01 | The catalogue reaches the client page | grep page-warm.html | contains 'b04-first-1786776736' | found | PASS |
| CP02 | Within the TTL the page still shows the old snapshot | grep page-within-ttl.html | does not contain 'b04-later-1786776736' | absent | PASS |
| CP03 | Past the TTL the new resource appears | grep page-past-ttl.html | contains 'b04-later-1786776736' | found | PASS |
| CP04 | and the original is still there | grep page-past-ttl.html | contains 'b04-first-1786776736' | found | PASS |
| CP05 | The page still renders with the server gone | grep page-server-down.html | contains 'b04-first-1786776736' | found | PASS |
| CP06 | Rendering did not wait on the unreachable server | seconds to render | < 15 | 0 | PASS |
| CP07 | The view recovers once the server is back | grep page-recovered.html | contains 'b04-later-1786776736' | found | PASS |

#### Summary

- catalog_ttl_seconds: 10
- render_seconds_with_server_down: 0

#### Artifacts

- page after warm-up: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260815153215-e2e-test/catalog-cache-ttl/page-warm.html
- page within TTL: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260815153215-e2e-test/catalog-cache-ttl/page-within-ttl.html
- page past TTL: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260815153215-e2e-test/catalog-cache-ttl/page-past-ttl.html
- page while the server is down: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260815153215-e2e-test/catalog-cache-ttl/page-server-down.html
- page after recovery: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260815153215-e2e-test/catalog-cache-ttl/page-recovered.html

