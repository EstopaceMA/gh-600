$ErrorActionPreference = "Stop"

$inputObj = [Console]::In.ReadToEnd() | ConvertFrom-Json
$toolName = $inputObj.toolName
$toolArgsRaw = $inputObj.toolArgs  # JSON string

# Resolve from the script so every working directory reuses the same logs.
$logDir = Join-Path (Split-Path -Parent $PSScriptRoot) "logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

# Example redaction logic.
# GitHub does not currently provide built-in secret redaction for hooks.
# This example shows one possible approach; many organizations prefer to
# forward events to a centralized logging system that handles redaction.
# Redact sensitive patterns before logging.
# Adjust these patterns to match your organization's needs.
$redactedToolArgs = $toolArgsRaw `
  -replace 'ghp_[A-Za-z0-9]{20,}', '[REDACTED_TOKEN]' `
  -replace 'gho_[A-Za-z0-9]{20,}', '[REDACTED_TOKEN]' `
  -replace 'ghu_[A-Za-z0-9]{20,}', '[REDACTED_TOKEN]' `
  -replace 'ghs_[A-Za-z0-9]{20,}', '[REDACTED_TOKEN]' `
  -replace 'Bearer [A-Za-z0-9_\-\.]+', 'Bearer [REDACTED]' `
  -replace '--password[= ][^ ]+', '--password=[REDACTED]' `
  -replace '--token[= ][^ ]+', '--token=[REDACTED]'

# Log attempted tool use with redacted toolArgs.
(@{
  event    = "preToolUse"
  toolName = $toolName
  toolArgs = $redactedToolArgs
} | ConvertTo-Json -Compress) | Add-Content -Path "$logDir/audit.jsonl"

if ($toolName -ne "bash") { exit 0 }

# Parse toolArgs JSON string.
$toolArgs = $null
try { $toolArgs = $toolArgsRaw | ConvertFrom-Json } catch { exit 0 }

$command = $toolArgs.command

# ---------------------------------------------------------------------------
# Demo-only deny rule for safe testing.
# This blocks a harmless test command so you can validate the deny flow.
# Remove this rule after confirming your hooks work as expected.
# ---------------------------------------------------------------------------
if ($command -match 'COPILOT_HOOKS_DENY_DEMO') {
  Deny "Blocked demo command (test rule). Remove this rule after validating hooks."
}

function Deny([string]$reason) {
  # Redact sensitive patterns from command before logging.
  $redactedCommand = $command `
    -replace 'ghp_[A-Za-z0-9]{20,}', '[REDACTED_TOKEN]' `
    -replace 'gho_[A-Za-z0-9]{20,}', '[REDACTED_TOKEN]' `
    -replace 'ghu_[A-Za-z0-9]{20,}', '[REDACTED_TOKEN]' `
    -replace 'ghs_[A-Za-z0-9]{20,}', '[REDACTED_TOKEN]' `
    -replace 'Bearer [A-Za-z0-9_\-\.]+', 'Bearer [REDACTED]' `
    -replace '--password[= ][^ ]+', '--password=[REDACTED]' `
    -replace '--token[= ][^ ]+', '--token=[REDACTED]'

  # Log the denial decision with redacted command.
  (@{
    event    = "policyDeny"
    toolName = "bash"
    command  = $redactedCommand
    reason   = $reason
  } | ConvertTo-Json -Compress) | Add-Content -Path "$logDir/audit.jsonl"

  (@{
    permissionDecision = "deny"
    permissionDecisionReason = $reason
  } | ConvertTo-Json -Compress)

  exit 0
}

if ($command -match '\b(sudo|su|runas)\b') { Deny "Privilege escalation requires manual approval." }
if ($command -match 'rm\s+-rf\s*/(\s|$)|rm\s+.*-rf\s*/(\s|$)') { Deny "Destructive operations targeting the filesystem root require manual approval." }
if ($command -match '\b(mkfs|dd|format)\b') { Deny "System-level destructive operations are not allowed via automated execution." }
if ($command -match 'curl.*\|\s*(bash|sh)|wget.*\|\s*(bash|sh)') { Deny "Download-and-execute patterns require manual approval." }

exit 0
