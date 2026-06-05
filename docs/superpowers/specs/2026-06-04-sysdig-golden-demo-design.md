# Sysdig On-Prem Golden Demo - Design

- Date: 2026-06-04
- Status: Draft for review
- Owner: Aaron Miles

## 1. Goal

A repeatable "golden demo" that walks a customer through the full lifecycle of a
preventable breach and shows where Sysdig Secure could have stopped it at three
distinct points. The emotional payload: a vulnerable customer-admin portal leaks
its entire customer database to an attacker, and the only control that actually
catches it at runtime is the Sysdig agent on the node.

The demo is explicitly built for an **air-gapped on-prem customer**. Nothing
reaches the internet at any point. The narrative leans into the fact that
air-gapped does not mean safe: the vulnerable image still got in through the
registry, and a foothold already inside the environment weaponized it. No
outbound internet was ever needed.

## 2. The narrative - "three places we could have stopped it"

A developer builds a customer portal on a component with a well-known public
CVE, ignores every warning, ships it, and an attacker already inside the
environment steals the customer database with a single request. Woven through
the flow, three intervention points the presenter calls out live:

1. **Build time** - `sysdig-cli-scanner` flags the CVE. "We could have stopped
   here and never built the image."
2. **Deploy time** - the Sysdig admission controller warns the workload violates
   policy. "We could have stopped here and refused the deploy." The developer
   force-deploys anyway.
3. **Runtime** - a Sysdig response action pauses the container mid-attack. "And
   if it got this far, we stop it here, before a single row leaves."

## 3. Audience and environment

- Live presenter walking a customer through the flow (not a self-service lab).
- The customer provides, and Aaron will have ready at test time:
  - The on-prem Sysdig Secure backend.
  - A Kubernetes cluster with the Sysdig agent installed.
  - The Sysdig admission controller installed.
- This repo provides everything else: the vulnerable app, the database, the
  Kubernetes manifests, the exploit scripts, and the presenter runbook.
- Image validation during build uses `sysdig-cli-scanner` (preferred) or trivy
  locally. Scanner auth/offline config is sorted at test time.

## 4. Vulnerability choice - CVE-2017-5638 (Apache Struts2)

Chosen over Log4Shell (CVE-2021-44228) deliberately. Rationale:

- **Reflected (non-blind) RCE.** The OGNL injection in the Jakarta Multipart
  parser runs an attacker-supplied command and returns its output in the HTTP
  response. This means the stolen data comes back in plain text in the
  attacker's terminal from a single curl. This is the "explosive" moment the
  demo is built around. Log4Shell is blind - the data would have to be
  exfiltrated to a listener and reviewed later in a capture.
- **Still spawns a shell.** The exploit makes the JVM run `java -> sh -> <cmd>`,
  which is wildly anomalous for a web process. The Sysdig agent sees this at the
  syscall level, so the runtime-detection and response-action story is fully
  intact.
- **Famous CVE the scanner flags.** Keeps the build-time scan and admission
  controller story unchanged.
- **The Equifax story.** CVE-2017-5638 is the exact bug behind the Equifax
  breach (147M customer records). For a customer worried about customer data,
  "this is how Equifax happened" is a devastating talk track.
- **No attacker callback infrastructure.** Unlike Log4Shell, a reflected RCE
  needs no LDAP server, no staged payload class, and no reverse-shell listener.
  One curl in, data out. This both simplifies the build and suits the air-gapped
  story (nothing phones anywhere).

## 5. The exploit - a sequence of single curls

The attacker (represented by the presenter, simulating a foothold already inside
the air-gapped environment) sends crafted `Content-Type` headers to the portal's
public NodePort. Each curl is more damning than the last and each returns its
result in plain text:

1. **Prove RCE** - run `id` / `hostname`. Confirms code execution and spawns a
   shell child of the JVM.
2. **Steal DB credentials** - run `env | grep -i PG`. The Postgres credentials
   (injected into the portal pod from a Kubernetes Secret as env vars) come back
   in plain text.
3. **Steal the customer table** - run a Postgres dump (`pg_dump` and/or
   `psql -c 'SELECT name,email,card FROM customers'`) using the creds from step
   2. The entire customer PII table prints in the terminal.

No data leaves the cluster. The "theft" is the data being returned to the
internal attacker over the existing HTTP response.

## 6. Components - all built here, all self-contained

- **`app/`** - the vulnerable "customer admin portal." A minimal Struts2 web
  application (WAR) on a vulnerable `struts2-core` (2.3.x or 2.5.x pre-fix),
  deployed on an older Tomcat + JDK 8 base image. Dressed up as a plausible
  customer-admin / order portal. The base image also carries a rich set of CVEs,
  which strengthens the scan story.
- **`db/`** - Postgres with an init script seeding a `customers` table of fake
  PII (names, emails, card numbers). Credentials injected into the portal pod
  via a Kubernetes Secret -> environment variables. This is exactly what the
  attacker steals in exploit step 2.
- **`k8s/`** - namespace, Postgres (Deployment/Service/Secret/initdb ConfigMap),
  portal (Deployment/Service as NodePort/Secret).
- **`scripts/`** - `build.sh` (build + load images into the customer registry),
  `scan.sh` (sysdig-cli-scanner), `exploit.sh` (the curls), `reset.sh`
  (teardown / re-arm between runs).
- **`README.md` + `docs/runbook.md`** - the presenter talk track, screen by
  screen, and the Sysdig-side configuration the presenter sets up.

There is intentionally **no attacker pod, no LDAP server, and no listener** -
the reflected RCE removes the need for them.

Optional (not required for the core flow): a tiny internal `jumpbox/` pod to run
the curls from inside the cluster, for maximum "internal foothold" realism. The
NodePort is reachable from the presenter's internal network regardless.

## 7. Runtime detection - rules tripped

Target policy: **Sysdig Runtime Threat Detection** (65/65 high-severity rules,
enabled), per the local ruleset correlation in `~/GitHub/falco-rules`.

| Exploit step | Rule | Priority |
|---|---|---|
| JVM spawns a shell (any step) | anomalous shell spawned by a web/Java process | to validate |
| `env \| grep` for DB creds | Dump Sensitive Environment Variables | CRITICAL |
| `pg_dump` / DB dump | Database Dump Command Detected | WARNING |

The guaranteed CRITICAL on screen is **Dump Sensitive Environment Variables**
(the rule requires `env`/`printenv` piped to a read util such as `grep` with a
piped stdin - exploit step 2 is engineered to match it exactly). The exact rule
names and severities for the shell-spawn signal will be validated against the
live ruleset during implementation, and the curls tuned to match the
highest-severity rules that fire reliably.

A **Capture** response action is attached to the policy so the presenter can
review the syscall capture afterward. Because Sysdig records read/write syscall
buffers, the captured event contains the actual stolen rows - a golden review
artifact.

## 8. Two runs, one app - the before/after

The demo runs the same exploit twice. The only thing that changes is whether
Sysdig is allowed to act.

- **Run 1 - monitoring only.** The curls return DB creds and the full customer
  table in plain text. Events and the capture land in Sysdig. Talk track: "That
  happened in a split second. No human responds that fast."
- **Run 2 - response action enabled.** Identical curls. The Sysdig policy now
  has a **Pause container** action on the early detection (shell spawn / env
  dump). The pod freezes the instant the web app does something it should never
  do, before the customer-table dump runs. The curl hangs and returns nothing.
  Talk track: "Same request. The only thing I changed was letting Sysdig act.
  The data never moved."

Pause is chosen over Kill so the frozen container is preserved for forensics and
the "we caught it mid-act" visual is stronger.

## 9. Air-gap constraints (hard requirements)

- All images (portal, Postgres) are pre-built and pre-loaded into the customer's
  registry or onto the nodes. No pulls from public registries during the demo.
- No tool is downloaded at runtime. Everything the exploit uses (`psql`,
  standard shell utilities) is present in the images by design.
- The exploit, data theft, and all traffic stay inside the cluster / internal
  network. Nothing egresses.
- `sysdig-cli-scanner` runs in its air-gapped / offline-database mode. The exact
  config is documented in the runbook and finalized at test time.

## 10. Repo layout

```
golden-demo-workflow/
  README.md                      # entry point + talk track summary
  app/                           # vulnerable Struts2 customer portal
    pom.xml
    src/...
    Dockerfile
  db/
    initdb/seed.sql              # fake customer PII
  k8s/
    00-namespace.yaml
    10-postgres.yaml
    20-portal.yaml
  scripts/
    build.sh
    scan.sh
    exploit.sh
    reset.sh
  docs/
    runbook.md                   # detailed presenter guide
    rule-mapping.md              # which curl trips which rule
  jumpbox/                       # optional internal-attacker pod
```

## 11. Sysdig-side configuration (documented, presenter performs)

These are not coded in the repo; the runbook gives click-by-click steps:

- Confirm the **Sysdig Runtime Threat Detection** policy is enabled and scoped to
  the demo namespace.
- Add a **Pause container** response action to the policy (enabled only for
  Run 2).
- Add a **Capture** response action to the policy.
- Confirm the admission controller policy that the vulnerable image violates, and
  how to force-deploy past the warning.

## 12. Out of scope / Phase 2 (parked)

- **Remediation epilogue** - patch the component, rebuild, rescan clean,
  redeploy, admission passes. Documented as a Phase 2 option; the presenter
  currently prefers the "three places we could have stopped it" framing told as
  the attack happens.
- **Reverse-shell / network-relay exfiltration escalation** - an optional
  additional beat that trips more CRITICAL rules (Reverse Shell Detected,
  Network Relay Binary Exfiltration) at the cost of reintroducing an in-cluster
  listener.
- **External / over-the-internet attacker** - off-narrative for this air-gapped
  customer.

## 13. Open items to validate during implementation

- Exact Struts2 + Tomcat + JDK 8 version combination that builds cleanly and is
  reliably exploitable by the CVE-2017-5638 OGNL payload.
- Exact rule names and severities for the shell-spawn signal in the live tenant;
  tune the curls to the highest-severity reliable rules.
- Whether `pg_dump` vs `psql -c 'SELECT ...'` is the better DB-theft command for
  both readable output and matching Database Dump Command Detected.
- `sysdig-cli-scanner` offline/air-gapped configuration.
- NodePort reachability from the presenter's position on the customer network.
- Response/detection latency, and the tunable delay needed so the Pause action
  reliably wins the race in Run 2.

## 15. Findings from Plan 1 execution (2026-06-04)

Plan 1 (the locally-verifiable core) was built and verified end to end. Key
findings that feed into Plan 2:

- **Exploit confirmed.** CVE-2017-5638 returns command output reflected in the
  HTTP response. The working trigger is a `POST` with a small body
  (`--data 'x=1'`) and the OGNL expression in the `Content-Type` header; a plain
  GET does not invoke the Jakarta multipart parser path. The server closes the
  connection after the payload flushes, so curl exits 18 (benign, suppressed).
  RCE runs as `root`. All three beats proven: `id`, env-dump of DB creds, and a
  full `pg_dump` of the customer table.
- **Image architecture.** Images were built on Apple Silicon (colima) and are
  therefore `arm64`. The base tags were substituted to arm64-available ones:
  build stage `maven:3.6.3-amazoncorretto-8`, runtime `tomcat:8.5.99-jre8-temurin`.
  For Plan 2, build for the cluster's architecture (`docker build --platform
  linux/amd64 ...` if the on-prem nodes are amd64) and pre-load into the
  registry.
- **Base-image CVE count.** `tomcat:8.5.99` is a recent 8.5 patch, so the bonus
  base-image CVEs are fewer than a truly old tag would give. The headline
  CVE-2017-5638 lives in the WAR's `struts2-core-2.5.10.jar`, so the scan story
  holds regardless. If a richer base-image finding list is wanted on screen,
  pin an older Tomcat/JRE base in Plan 2.
- **JDBC driver registration.** Tomcat's web classloader did not auto-discover
  the Postgres JDBC driver via ServiceLoader; `CustomerAction` calls
  `Class.forName("org.postgresql.Driver")` explicitly. Carry this forward.
- **Runbook cosmetic.** `env | grep -i PG` also matches `GPG_KEYS` (noise). Use a
  tighter filter (e.g. `grep PGPASSWORD`) in the on-stage exploit for a cleaner
  read, while keeping the `env | grep` shape that the "Dump Sensitive
  Environment Variables" rule needs.

## 16. Deployment target (decided 2026-06-05)

The demo is built and tested on a real cluster (the "air-gapped on-prem"
framing in sections 2/9 becomes talk-track; the backend is customer-managed
on-prem Sysdig, not SaaS, which is the literal truth being narrated).

- **Cluster:** EKS `cni-test-cluster`, AWS account `059797578166`,
  region `ap-southeast-2`. Nodes are **amd64** (t3.medium, Amazon Linux 2), so
  images must be built `--platform linux/amd64`.
- **Auth:** kubectl and AWS both use `AWS_PROFILE=draios-dev` (that SSO role is
  admin in `059797578166`; the machine's default AWS profile is a different
  account, `892165838036`, so the profile must be set explicitly for ECR work).
- **Registry:** ECR in `059797578166` (currently empty). Plan 2 creates a
  `golden-demo/portal` repository there; EKS nodes pull natively via their node
  role (same account).
- **Exposure:** the portal Service is a **LoadBalancer** (must be reachable from
  Aaron's Mac to fire the exploit curl). Supersedes the NodePort default in
  section 11.
- **Sysdig backend:** an on-prem Monitor+Secure stack built by the "OSC"
  (Onprem Stack Creator) Jenkins job; cluster name `aaron-miles-osc-23825`. The
  on-prem Sysdig Secure URL and a Secure API token are runbook/test-time inputs
  (needed for `sysdig-cli-scanner` and UI backlinks).
- **Agent + admission:** `sysdig-agent-shield` (cluster + host shield) and the
  `sysdig-agent-shield-cluster-admission-control` validating webhook are already
  installed in the `sysdig-agent` namespace. Whether admission warns vs blocks
  on the vulnerable image is a Sysdig-side policy setting to verify at deploy
  time (the narrative needs warn-then-deploy-anyway, not a hard block).

## 14. Success criteria

- One `build.sh` produces all images and loads them into the target registry.
- `scan.sh` shows CVE-2017-5638 (and base-image CVEs) flagged.
- Deploying the portal triggers an admission-controller warning that can be
  force-bypassed.
- `exploit.sh` Run 1 returns DB creds and the full customer table in plain text.
- Sysdig fires at least one CRITICAL runtime event and produces a reviewable
  capture containing the stolen rows.
- `exploit.sh` Run 2, with the Pause action enabled, freezes the pod before the
  customer table is returned; the curl returns nothing.
- `reset.sh` returns the environment to a clean state for a repeat run.
```
