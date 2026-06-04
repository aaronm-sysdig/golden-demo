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
