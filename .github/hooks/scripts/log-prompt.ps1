$ErrorActionPreference = "Stop"

$inputObj = [Console]::In.ReadToEnd() | ConvertFrom-Json

$timestampMs = $inputObj.timestamp
$cwd = $inputObj.cwd
$prompt = $inputObj.prompt

# Optional example redaction. Adjust to match your organization’s needs.
$redactedPrompt = $prompt -replace 'ghp_[A-Za-z0-9]{20,}', '[REDACTED_TOKEN]'

# Resolve from the script so every working directory reuses the same logs.
$logDir = Join-Path (Split-Path -Parent $PSScriptRoot) "logs"
if (-not (Test-Path $logDir)) {
  New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

$logEntry = @{
  event       = "userPromptSubmitted"
  timestampMs = $timestampMs
  cwd         = $cwd
  prompt      = $redactedPrompt
} | ConvertTo-Json -Compress

Add-Content -Path "$logDir/audit.jsonl" -Value $logEntry
exit 0
