# Golden Demo EKS Deploy (Plan 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy the vulnerable portal + Postgres to the EKS `cni-test-cluster`, exposed via a LoadBalancer, push the portal image to ECR, and prove the CVE-2017-5638 reflected-RCE data theft works over the internet-facing LoadBalancer while the Sysdig agent detects it at runtime.

**Architecture:** The portal image (built in Plan 1) is rebuilt for `linux/amd64`, pushed to ECR in the cluster's own account (`059797578166`), and run as a Deployment behind a `LoadBalancer` Service. Postgres runs as a second Deployment seeded from the existing `db/initdb/seed.sql` (mounted via a ConfigMap), with credentials in a Kubernetes Secret injected into both pods as env vars. The exploit script auto-discovers the LoadBalancer hostname and reuses the Plan 1 payload.

**Tech Stack:** EKS (Kubernetes), ECR, AWS CLI (`AWS_PROFILE=draios-dev`), `kubectl`, Docker (colima, buildx for amd64), the on-prem Sysdig Secure backend, `sysdig-cli-scanner`.

**Prerequisites for execution:**
- `kubectl` current context = `arn:aws:eks:ap-southeast-2:059797578166:cluster/cni-test-cluster`.
- `AWS_PROFILE=draios-dev` authenticates to account `059797578166` (set explicitly; the machine default profile is a different account).
- Docker running (colima). Build-time internet for base images.
- Tasks 5 (scan) and 6 (runtime detection) additionally need the on-prem Sysdig Secure URL and a Secure API token; the controller will provide these when those tasks start.

---

## Environment constants (used throughout)

- AWS account: `059797578166`, region: `ap-southeast-2`, profile: `draios-dev`
- ECR registry: `059797578166.dkr.ecr.ap-southeast-2.amazonaws.com`
- Portal image: `059797578166.dkr.ecr.ap-southeast-2.amazonaws.com/golden-demo/portal:vuln`
- Namespace: `golden-demo`

## File Structure

- `k8s/00-namespace.yaml` - the `golden-demo` namespace.
- `k8s/10-postgres.yaml` - Secret (DB creds), Postgres Deployment (seeded via the `pg-initdb` ConfigMap), ClusterIP Service `postgres`.
- `k8s/20-portal.yaml` - portal Deployment (ECR image, DB creds from the Secret as env), LoadBalancer Service `portal`.
- `scripts/build-push.sh` - create the ECR repo if needed, build the portal for `linux/amd64`, push.
- `scripts/deploy.sh` - apply namespace, create the `pg-initdb` ConfigMap from `db/initdb/seed.sql`, apply manifests, wait for rollout + LoadBalancer, print the URL.
- `scripts/exploit.sh` - discover the LoadBalancer hostname and run the Plan 1 exploit against it.
- `scripts/scan.sh` - scan the portal image with `sysdig-cli-scanner` against the on-prem backend.
- `scripts/reset.sh` - delete the namespace (deprovisions the ELB).

The `pg-initdb` ConfigMap is generated at deploy time from the single source of truth `db/initdb/seed.sql` (created in Plan 1) - it is not duplicated into a manifest.

---

## Task 1: Build and push the portal image to ECR

**Files:**
- Create: `scripts/build-push.sh`

- [ ] **Step 1: Write `scripts/build-push.sh`**

```bash
#!/usr/bin/env bash
# Build the portal for linux/amd64 and push to ECR in the cluster's account.
set -euo pipefail

export AWS_PROFILE=draios-dev
ACCOUNT=059797578166
REGION=ap-southeast-2
REPO=golden-demo/portal
TAG=vuln
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REGISTRY="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"
IMAGE="${REGISTRY}/${REPO}:${TAG}"

aws ecr describe-repositories --region "$REGION" --repository-names "$REPO" >/dev/null 2>&1 \
  || aws ecr create-repository --region "$REGION" --repository-name "$REPO" >/dev/null

aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"

# EKS nodes are amd64; the build host (colima) is arm64, so set the platform.
docker build --platform linux/amd64 -t "$IMAGE" "$ROOT/app"
docker push "$IMAGE"
echo "Pushed $IMAGE"
```

- [ ] **Step 2: Run it (the test for this task)**

Run:
```bash
chmod +x scripts/build-push.sh
./scripts/build-push.sh
```
Expected: ends with `Pushed 059797578166.dkr.ecr.ap-southeast-2.amazonaws.com/golden-demo/portal:vuln`.

- [ ] **Step 3: Verify the image is in ECR**

Run:
```bash
AWS_PROFILE=draios-dev aws ecr describe-images --region ap-southeast-2 \
  --repository-name golden-demo/portal --query 'imageDetails[].imageTags' --output text
```
Expected: `vuln`.

Note: if `docker build --platform linux/amd64` errors that the builder cannot produce amd64, enable it once with `docker buildx create --use` and retry, or build with `docker buildx build --platform linux/amd64 --load`. The image MUST be amd64 to run on the t3.medium nodes.

- [ ] **Step 4: Commit**

```bash
git add scripts/build-push.sh
git commit -m "Add ECR build-push script for the portal image"
```

---

## Task 2: Kubernetes manifests

**Files:**
- Create: `k8s/00-namespace.yaml`
- Create: `k8s/10-postgres.yaml`
- Create: `k8s/20-portal.yaml`

- [ ] **Step 1: Write `k8s/00-namespace.yaml`**

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: golden-demo
```

- [ ] **Step 2: Write `k8s/10-postgres.yaml`**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
  namespace: golden-demo
type: Opaque
stringData:
  username: portal
  password: s3cr3t
  database: customers
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
  namespace: golden-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: postgres:13
          env:
            - name: POSTGRES_USER
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: username
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: password
            - name: POSTGRES_DB
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: database
          ports:
            - containerPort: 5432
          volumeMounts:
            - name: initdb
              mountPath: /docker-entrypoint-initdb.d
          readinessProbe:
            exec:
              command: ["pg_isready", "-U", "portal"]
            initialDelaySeconds: 5
            periodSeconds: 5
      volumes:
        - name: initdb
          configMap:
            name: pg-initdb
---
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: golden-demo
spec:
  selector:
    app: postgres
  ports:
    - port: 5432
      targetPort: 5432
```

- [ ] **Step 3: Write `k8s/20-portal.yaml`**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: portal
  namespace: golden-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: portal
  template:
    metadata:
      labels:
        app: portal
    spec:
      containers:
        - name: portal
          image: 059797578166.dkr.ecr.ap-southeast-2.amazonaws.com/golden-demo/portal:vuln
          env:
            - name: PGHOST
              value: postgres
            - name: PGDATABASE
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: database
            - name: PGUSER
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: username
            - name: PGPASSWORD
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: password
          ports:
            - containerPort: 8080
          readinessProbe:
            httpGet:
              path: /
              port: 8080
            initialDelaySeconds: 20
            periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: portal
  namespace: golden-demo
spec:
  type: LoadBalancer
  selector:
    app: portal
  ports:
    - port: 80
      targetPort: 8080
```

Note: the DB password reaches the portal as a normal container env var (Kubernetes
materializes the Secret value into the environment). That is exactly what the
exploit's `env`-dump step steals, so the runtime story is unchanged from Plan 1.

- [ ] **Step 4: Validate the manifests (the test for this task)**

Run:
```bash
kubectl apply --dry-run=client -f k8s/00-namespace.yaml -f k8s/10-postgres.yaml -f k8s/20-portal.yaml
```
Expected: each resource prints `... (dry run)` with no schema errors.

- [ ] **Step 5: Commit**

```bash
git add k8s/
git commit -m "Add EKS manifests for namespace, Postgres, and portal (LoadBalancer)"
```

---

## Task 3: Deploy and reset scripts (live on EKS)

**Files:**
- Create: `scripts/deploy.sh`
- Create: `scripts/reset.sh`

- [ ] **Step 1: Write `scripts/deploy.sh`**

```bash
#!/usr/bin/env bash
# Deploy the golden demo to EKS and print the LoadBalancer URL.
set -euo pipefail

export AWS_PROFILE=draios-dev
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NS=golden-demo

kubectl apply -f "$ROOT/k8s/00-namespace.yaml"

# ConfigMap from the single source of truth (db/initdb/seed.sql).
kubectl create configmap pg-initdb \
  --from-file="$ROOT/db/initdb/seed.sql" \
  -n "$NS" --dry-run=client -o yaml | kubectl apply -f -

# Apply Postgres and the portal. Admission-controller warnings (if the Sysdig
# policy is in warn mode) print here but do not stop the apply.
kubectl apply -f "$ROOT/k8s/10-postgres.yaml"
kubectl apply -f "$ROOT/k8s/20-portal.yaml"

echo "Waiting for rollouts..."
kubectl rollout status deploy/postgres -n "$NS" --timeout=120s
kubectl rollout status deploy/portal -n "$NS" --timeout=180s

echo "Waiting for the LoadBalancer hostname..."
LB=""
for _ in $(seq 1 30); do
  LB=$(kubectl get svc portal -n "$NS" \
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  [ -n "$LB" ] && break
  sleep 10
done

if [ -z "$LB" ]; then
  echo "LoadBalancer hostname not assigned yet. Check: kubectl get svc portal -n $NS"
  exit 1
fi

echo "Portal LoadBalancer: http://${LB}/"
echo "Note: the ELB DNS can take 2-3 minutes to resolve after first assignment."
```

- [ ] **Step 2: Write `scripts/reset.sh`**

```bash
#!/usr/bin/env bash
# Tear down the demo (also deprovisions the ELB created by the LoadBalancer svc).
set -euo pipefail
export AWS_PROFILE=draios-dev
kubectl delete namespace golden-demo --ignore-not-found
echo "Deleted golden-demo namespace. The ELB deprovisions automatically."
```

- [ ] **Step 3: Deploy (the test for this task)**

Run:
```bash
chmod +x scripts/deploy.sh scripts/reset.sh
./scripts/deploy.sh
```
Expected: both rollouts succeed and a line `Portal LoadBalancer: http://<elb-hostname>/` prints. Capture any admission-controller warnings shown during `kubectl apply` and include them in your report (they are expected and are part of the demo narrative).

- [ ] **Step 4: Verify the portal serves and reads the DB over the LoadBalancer**

Run (replace `<LB>` with the hostname from Step 3; the ELB DNS may take 2-3 min to resolve, retry if curl fails to connect):
```bash
sleep 60
curl -s "http://<LB>/customers.action" | grep -i "example.com"
```
Expected: at least one seeded customer email renders, proving the portal is reachable from outside the cluster and connected to Postgres.

- [ ] **Step 5: Commit**

```bash
git add scripts/deploy.sh scripts/reset.sh
git commit -m "Add EKS deploy and reset scripts"
```

---

## Task 4: Exploit over the LoadBalancer

**Files:**
- Create: `scripts/exploit.sh`

- [ ] **Step 1: Write `scripts/exploit.sh`**

```bash
#!/usr/bin/env bash
# Discover the portal LoadBalancer and run the Plan 1 exploit against it.
set -euo pipefail
export AWS_PROFILE=draios-dev
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NS=golden-demo

LB=$(kubectl get svc portal -n "$NS" \
      -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
if [ -z "$LB" ]; then
  echo "Portal LoadBalancer not ready. Run ./scripts/deploy.sh first."
  exit 1
fi

echo "Target: http://${LB}/customers.action"
TARGET="http://${LB}/customers.action" exec "$ROOT/scripts/exploit-local.sh"
```

This reuses the exact payload from Plan 1's `scripts/exploit-local.sh` (which
already honors the `TARGET` env var), so there is one source of truth for the
exploit.

- [ ] **Step 2: Run the exploit (the test for this task)**

Run:
```bash
chmod +x scripts/exploit.sh
./scripts/exploit.sh
```
Expected, returned in plain text over the internet-facing LoadBalancer:
- STEP 1: `uid=0(root) gid=0(root) ...`
- STEP 2: the Postgres env vars including `PGPASSWORD=s3cr3t`
- STEP 3: the full customer table (names, emails, card numbers)

If STEP 1 does not return `uid=...`, confirm the ELB DNS resolves and the portal
is healthy (`kubectl get pods -n golden-demo`), then retry. Do not change the
payload - it is proven working in Plan 1.

- [ ] **Step 3: Commit**

```bash
git add scripts/exploit.sh
git commit -m "Add LoadBalancer exploit script reusing the Plan 1 payload"
```

---

## Task 5: Scan the image against the on-prem Sysdig backend

**Files:**
- Create: `scripts/scan.sh`

This task needs two inputs the controller will provide when the task starts:
`SYSDIG_SECURE_URL` (the OSC on-prem Secure URL) and `SECURE_API_TOKEN` (a Secure
API token). If they are not provided, report NEEDS_CONTEXT.

- [ ] **Step 1: Write `scripts/scan.sh`**

```bash
#!/usr/bin/env bash
# Scan the portal image with sysdig-cli-scanner against the on-prem backend.
# Requires env: SYSDIG_SECURE_URL, SECURE_API_TOKEN.
set -euo pipefail

: "${SYSDIG_SECURE_URL:?set SYSDIG_SECURE_URL to the on-prem Sysdig Secure URL}"
: "${SECURE_API_TOKEN:?set SECURE_API_TOKEN to a Sysdig Secure API token}"

ACCOUNT=059797578166
REGION=ap-southeast-2
IMAGE="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com/golden-demo/portal:vuln"

OS=$(uname -s | tr '[:upper:]' '[:lower:]')   # darwin
ARCH=$(uname -m)                               # arm64
[ "$ARCH" = "x86_64" ] && ARCH=amd64

BIN=./sysdig-cli-scanner
if [ ! -x "$BIN" ]; then
  VERSION=$(curl -sL https://download.sysdig.com/scanning/sysdig-cli-scanner/latest_version.txt)
  echo "Downloading sysdig-cli-scanner ${VERSION} (${OS}/${ARCH})..."
  curl -sL -o "$BIN" \
    "https://download.sysdig.com/scanning/bin/sysdig-cli-scanner/${VERSION}/${OS}/${ARCH}/sysdig-cli-scanner"
  chmod +x "$BIN"
fi

# build-push.sh already logged docker in to ECR, so the scanner can pull the image.
SECURE_API_TOKEN="$SECURE_API_TOKEN" "$BIN" --apiurl "$SYSDIG_SECURE_URL" "$IMAGE"
```

- [ ] **Step 2: Run the scan (the test for this task)**

Run (the controller will export the two env vars first):
```bash
chmod +x scripts/scan.sh
./scripts/scan.sh
```
Expected: the scanner completes and reports a vulnerability result that includes
`CVE-2017-5638`, and the scan appears in the on-prem Sysdig Secure UI under
Vulnerabilities. Paste the lines of output that reference the policy evaluation
result and CVE-2017-5638.

Note: a non-zero exit code is expected if the image fails the scan policy - that
is the demo's point. Capture the result rather than treating the exit code as a
failure.

- [ ] **Step 3: Commit**

```bash
git add scripts/scan.sh
git commit -m "Add sysdig-cli-scanner script targeting the on-prem backend"
```

---

## Task 6: Confirm runtime detection fires

**Files:** none created; this verifies the agent caught the exploit.

This task needs the Sysdig Secure UI (or API token). It confirms the runtime
half of the demo works before Plan 3 adds the response action.

- [ ] **Step 1: Ensure the agent is ready and re-run the exploit**

Run:
```bash
kubectl get pods -n sysdig-agent
```
Expected: `sysdig-agent-shield-host-*` pods are `1/1 Running` (host shield does
the syscall capture). If they are not ready, wait until they are, then run
`./scripts/exploit.sh` again to generate fresh activity.

- [ ] **Step 2: Verify events in Sysdig Secure**

In the on-prem Sysdig Secure UI, open Threats / Runtime events, scoped to the
`golden-demo` namespace, within ~2 minutes of running the exploit.
Expected: at least one CRITICAL detection - specifically **Dump Sensitive
Environment Variables** (from the `env | grep` step), and likely a shell-spawn
detection from the JVM. Record which rules fired and their severities.

This is the signal Plan 3's Pause response action will be attached to. If no
events appear, confirm the host-shield pods are Running, the agent is connected
to the on-prem collector, and the `golden-demo` workload is in the agent's scope;
note findings for follow-up.

---

## Self-Review Notes

- Spec coverage: this plan covers spec section 16 (EKS target, ECR, LoadBalancer,
  amd64, draios-dev profile) and the deploy/scan/exploit/reset scripts from
  section 6; it realizes the build-time scan (section 2 point 1) and runtime
  detection (section 7) on the live cluster. The Pause + Capture response actions
  and the two-run before/after (sections 7-8, 11) and the presenter runbook are
  deferred to Plan 3, which depends on this plan being deployed and detecting.
- Credential and name consistency: the Secret keys (`username`/`password`/
  `database`), the `postgres` Service name (= portal `PGHOST`), and the
  `golden-demo` namespace are consistent across `10-postgres.yaml`,
  `20-portal.yaml`, and `deploy.sh`. The ECR image URI is identical in
  `build-push.sh`, `20-portal.yaml`, and `scan.sh`.
- The exploit is not duplicated: `exploit.sh` delegates to the Plan 1
  `exploit-local.sh` via the `TARGET` env var.
- No placeholders: every file has complete content; live-cluster tasks have exact
  commands and expected output. The only runtime-supplied values are
  `SYSDIG_SECURE_URL` and `SECURE_API_TOKEN` for Task 5, explicitly flagged.
```
