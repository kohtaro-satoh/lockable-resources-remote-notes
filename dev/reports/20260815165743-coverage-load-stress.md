# Coverage — load-stress

- plugin: `bdca858`
- source: `/home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260815165743-coverage-load-stress/site/jacoco.csv`
- measured by attaching the JaCoCo agent to the four controllers, so this is what the suite
  drives through a running Jenkins — not what the unit tests reach.

## Totals

| Scope | Line | Branch |
|---|---|---|
| remote-related | 54.4% (701/1288) | 34.4% (188/546) |
| whole plugin | 38.7% (1776/4588) | 26.8% (600/2238) |

## Remote classes this suite never entered

Nothing here is necessarily wrong: some of it is only reachable from a unit test by
design. It is the list to read before assuming a suite covers something.

| Class | Lines missed |
|---|---|
| `actions.ResourcesResource` | 43 |
| `remote.Resource` | 16 |
| `remote.RemoteApiException` | 13 |
| `remote.RemoteCatalog` | 13 |
| `remote.ExtraResource` | 8 |
| `actions.InvalidFieldException` | 2 |

## Remote classes with the most unreached lines

| Class | Line | Branch | Lines missed |
|---|---|---|---|
| `remote.RemoteLockSession` | 50.4% | 33.8% | 125 |
| `remote.RemoteApiClient` | 50.9% | 32.5% | 111 |
| `actions.AcquireRouter` | 51.7% | 28.1% | 42 |
| `remote.RemoteCatalogCache` | 17.5% | 0.0% | 33 |
| `remote.RemoteResolver` | 60.7% | 42.2% | 33 |
| `actions.RemoteApiV1Action` | 64.7% | 70.8% | 18 |
| `remote.RemoteLockManager` | 80.7% | 59.5% | 17 |
| `lockableresources.DescriptorImpl` | 5.6% | 0.0% | 17 |
| `lockableresources.RemoteConnection` | 50.0% | 23.3% | 17 |
| `remote.RemoteCredentials` | 50.0% | 50.0% | 14 |
| `remote.Entry` | 48.0% | 21.4% | 13 |
| `remote.RemoteLockRouting` | 57.7% | 35.3% | 11 |
| `remote.RemoteClientRegistry` | 54.5% | 20.0% | 10 |
| `actions.LeaseResource` | 60.9% | 30.0% | 9 |
| `remote.RemoteQueueEntry` | 87.9% | 62.5% | 4 |

