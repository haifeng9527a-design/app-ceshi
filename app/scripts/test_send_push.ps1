# Test send_push Edge Function (simulate one push).
# Usage (from app dir):
#   .\scripts\test_send_push.ps1
#     -> uses fake receiverId; response "No device tokens" means endpoint is OK.
#   .\scripts\test_send_push.ps1 -ReceiverId "YOUR_FIREBASE_UID"
#     -> send real push to that user (UID from Firebase Console > Authentication > Users).
# Env: SUPABASE_URL, SUPABASE_ANON_KEY (auto-loaded from app\.env if present).

param(
    [Parameter(Mandatory = $false)]
    [string] $ReceiverId = "test-receiver-no-tokens",
    [string] $Title = "Test push",
    [string] $Body = "This is a test message"
)

$ErrorActionPreference = "Stop"
$appRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
foreach ($envPath in @( (Join-Path $appRoot ".env"), (Join-Path (Get-Location) ".env") )) {
    if (Test-Path $envPath) {
        Get-Content $envPath -Encoding UTF8 | ForEach-Object {
            $line = $_.Trim()
            if ($line -and $line -notmatch '^\s*#' -and $line -match '^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
                [Environment]::SetEnvironmentVariable($matches[1], $matches[2].Trim().Trim('"').Trim("'"), "Process")
            }
        }
        break
    }
}

$url = $env:SUPABASE_URL
$anonKey = $env:SUPABASE_ANON_KEY
if (-not $url -or -not $anonKey) {
    Write-Host "Error: SUPABASE_URL and SUPABASE_ANON_KEY required (e.g. from app\.env)" -ForegroundColor Red
    exit 1
}

$functionUrl = "$url/functions/v1/send_push"
$body = @{
    receiverId = $ReceiverId
    title      = $Title
    body       = $Body
} | ConvertTo-Json -Compress

Write-Host "POST $functionUrl"
Write-Host "Body: $body"
Write-Host ""

try {
    $response = Invoke-RestMethod -Uri $functionUrl -Method Post -Body $body -ContentType "application/json" -Headers @{
        "Authorization" = "Bearer $anonKey"
    }
    Write-Host "Response:"
    if ($response -is [string]) {
        Write-Host $response
    } else {
        $response | ConvertTo-Json -Depth 5
    }
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
    $reader.BaseStream.Position = 0
    $responseBody = $reader.ReadToEnd()
    Write-Host "HTTP $statusCode"
    Write-Host $responseBody
    exit 1
}
