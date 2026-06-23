#!/usr/bin/env bash
# Triggers rules in "Sysdig AI Runtime Notable Events" policy for demo purposes.
# Run from inside the claude-demo pod: ./trigger-ai-rules.sh
# Seconds to pause between steps - override with DEMO_PAUSE=N
PAUSE=${DEMO_PAUSE:-1.5}

pause() {
  echo ""
  sleep "$PAUSE"
  echo ""
}

header() {
  echo ""
  echo "  ─────────────────────────────────────────────────────"
  echo "  $1"
  echo "  ─────────────────────────────────────────────────────"
  echo ""
}

echo ""
echo "  Sysdig AI Runtime Notable Events - Rule Trigger Demo"
echo "  Policy covers agentic AI tools: Claude Code, Gemini CLI, Codex CLI"
echo "  Each step triggers a specific Falco detection rule."
echo ""
pause

# ── Rule 22: CLI Agent Impersonation ──────────────────────────────────────────
header "Rule: CLI Agent Impersonation Detected"
echo "  Scenario: attacker drops a malicious binary named 'claude' in /tmp"
echo "  and executes it to blend into expected AI agent process activity."
echo ""
echo "  Falco fires when proc.name = 'claude' but exepath is not a known"
echo "  Claude install path (npm, snap, bun, system bin, VS Code extension)."
echo ""
echo "  $ cp /bin/sh /tmp/claude && /tmp/claude -c 'id'"
echo ""
pause

cp /bin/sh /tmp/claude
/tmp/claude -c 'id' 2>/dev/null || true
rm -f /tmp/claude

echo ""
echo "  -> Sysdig: CLI Agent Impersonation Detected"
pause

# ── Rule 1: Unauthorized Config Dir Access ────────────────────────────────────
header "Rule: Unauthorized Process Accessed Claude Code Configuration Directory"
echo "  Scenario: a non-Claude process reads files under ~/.claude/"
echo "  Attacker harvests session data, task history, or stored settings."
echo ""
echo "  Falco fires on any open/read of ~/.claude/** from a process"
echo "  outside the Claude Code process family."
echo ""
echo "  $ cat ~/.claude/settings.json"
echo ""
pause

cat ~/.claude/settings.json 2>/dev/null | head -5 || echo "  (file read attempted)"

echo ""
echo "  -> Sysdig: Unauthorized Process Accessed Claude Code Configuration Directory"
pause

# ── Rule 21: Agent Credential File Theft ─────────────────────────────────────
header "Rule: Read Agent CLI Credential File Untrusted"
echo "  Scenario: non-Claude process opens ~/.claude/.credentials.json"
echo "  This file holds OAuth access + refresh tokens for the Anthropic API."
echo ""
echo "  Falco fires on open_read of the credential file by any process"
echo "  outside the owning agent - including cross-agent theft (e.g. Gemini"
echo "  reading Claude's tokens after a prompt injection)."
echo ""
echo "  $ cat ~/.claude/.credentials.json | wc -c"
echo ""
pause

# Safe: pipe to wc -c so token values never appear on screen
BYTES=$(cat ~/.claude/.credentials.json 2>/dev/null | wc -c || echo 0)
echo "  Credential file read: ${BYTES} bytes (tokens redacted)"

echo ""
echo "  -> Sysdig: Read Agent CLI Credential File Untrusted"
pause

# ── Rule 3: Risky CLI Arguments ───────────────────────────────────────────────
header "Rule: Claude Code Executed with Risky CLI Arguments"
echo "  Scenario: Claude Code is started with --dangerously-skip-permissions,"
echo "  disabling all built-in safety checks and approval prompts."
echo "  Combined with prompt injection this gives an attacker full RCE"
echo "  through the agent with no confirmation gates."
echo ""
echo "  Falco fires on process spawn of claude with these flags in cmdline."
echo ""
echo "  $ claude --dangerously-skip-permissions --print 'say: demo'"
echo ""
pause

claude --dangerously-skip-permissions --print "say: demo complete" 2>/dev/null 1>/dev/null || true

echo ""
echo "  -> Sysdig: Claude Code Executed with Risky CLI Arguments"
pause

# ── Rule 20: Non-Agent Process Connecting to LLM API ─────────────────────────
header "Rule: Non-Agent Process Connecting to LLM API"
echo "  Scenario: a process executing from /tmp makes a DNS lookup for"
echo "  api.anthropic.com - the pattern seen in HONESTCUE and Xanthorox"
echo "  malware families that use commercial LLM APIs as C2 channels or"
echo "  to generate second-stage payloads dynamically at runtime."
echo ""
echo "  Falco fires on DNS response for LLM API domains (api.anthropic.com,"
echo "  api.openai.com, generativelanguage.googleapis.com) where the"
echo "  calling process exepath starts with /tmp/, /dev/shm/, or /run/user/"
echo ""
echo "  $ cp /usr/bin/curl /tmp/updater"
echo "  $ /tmp/updater -s https://api.anthropic.com/ 2>/dev/null"
echo ""
pause

cp /usr/bin/curl /tmp/updater
/tmp/updater -sf https://api.anthropic.com/ 2>/dev/null | head -1 || true
rm -f /tmp/updater

echo ""
echo "  -> Sysdig: Non-Agent Process Connecting to LLM API"
pause


# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "  Demo complete."
echo "  Check the Sysdig console for triggered events under:"
echo "  Threats > Activity Audit > Policy: Sysdig AI Runtime Notable Events"
echo ""
