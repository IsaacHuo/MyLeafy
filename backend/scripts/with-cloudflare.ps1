param(
    [Parameter(Mandatory, Position=0)][string]$Command,
    [Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments
)
$ErrorActionPreference = 'Stop'
$taskCredentialPath = Join-Path $env:LOCALAPPDATA 'MyLeafyMigration/cloudflare-token.dpapi'
if (-not (Test-Path -LiteralPath $taskCredentialPath)) {
    throw 'Cloudflare credential is missing. Set CLOUDFLARE_API_TOKEN securely, or provision the Windows DPAPI credential.'
}
$taskPreviousToken = $env:CLOUDFLARE_API_TOKEN
$taskPreviousAccount = $env:CLOUDFLARE_ACCOUNT_ID
try {
    $taskSecret = Get-Content -LiteralPath $taskCredentialPath | ConvertTo-SecureString
    $env:CLOUDFLARE_API_TOKEN = [System.Net.NetworkCredential]::new('', $taskSecret).Password
    $env:CLOUDFLARE_ACCOUNT_ID = 'be7d850d4b5046381fb909251b4df675'
    & $Command @Arguments
    $taskResult = $LASTEXITCODE
} finally {
    $env:CLOUDFLARE_API_TOKEN = $taskPreviousToken
    $env:CLOUDFLARE_ACCOUNT_ID = $taskPreviousAccount
    Remove-Variable taskSecret -ErrorAction SilentlyContinue
}
exit $taskResult
