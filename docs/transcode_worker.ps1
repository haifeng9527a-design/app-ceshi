$ErrorActionPreference = "Stop"

$SUPABASE_URL = if ($env:SUPABASE_URL) { $env:SUPABASE_URL } else { "https://theqizksqjrylsnrrrhx.supabase.co" }
$SUPABASE_ANON_KEY = if ($env:SUPABASE_ANON_KEY) { $env:SUPABASE_ANON_KEY } else { "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRoZXFpemtzcWpyeWxzbnJycmh4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA2MTA4NzQsImV4cCI6MjA4NjE4Njg3NH0.8GYXS6D1rcjp3KZOTJ28e7hJfu0mxiD5LHZiTq6oDVc" }
$BUCKET = "chat-media"
$FFMPEG = (Get-Command ffmpeg -ErrorAction SilentlyContinue).Source
if (-not $FFMPEG) {
  $FFMPEG = "C:\Program Files\FFmpeg\bin\ffmpeg.exe"
}

$headers = @{
  "apikey"        = $SUPABASE_ANON_KEY
  "Authorization" = "Bearer $SUPABASE_ANON_KEY"
}

$tmpDir = Join-Path $PSScriptRoot "tmp"
if (!(Test-Path $tmpDir)) {
  New-Item -ItemType Directory -Path $tmpDir | Out-Null
}

$queryUrl = "$SUPABASE_URL/rest/v1/chat_messages?select=id,media_url&message_type=eq.video&media_url_transcoded=is.null&media_url=not.is.null&limit=20"
$rows = Invoke-RestMethod -Headers $headers -Uri $queryUrl -Method Get

foreach ($row in $rows) {
  $id = $row.id
  $mediaUrl = $row.media_url
  if (-not $id -or -not $mediaUrl) { continue }

  $inputPath = Join-Path $tmpDir "$id.source"
  $outputPath = Join-Path $tmpDir "$id.mp4"

  Write-Host "Downloading: $mediaUrl"
  Invoke-WebRequest -Uri $mediaUrl -OutFile $inputPath

  Write-Host "Transcoding: $id"
  & $FFMPEG -y -i "$inputPath" -vf "scale=640:-2" -c:v libx264 -profile:v baseline -level 3.0 -pix_fmt yuv420p -preset veryfast -crf 28 -c:a aac -b:a 96k -movflags +faststart "$outputPath"

  if (!(Test-Path $outputPath)) {
    Write-Host "Transcode failed: $id"
    continue
  }

  $objectPath = "chat/transcoded/$id.mp4"
  $uploadUrl = "$SUPABASE_URL/storage/v1/object/$BUCKET/$objectPath"
  $uploadHeaders = @{
    "apikey"        = $SUPABASE_ANON_KEY
    "Authorization" = "Bearer $SUPABASE_ANON_KEY"
    "x-upsert"      = "true"
  }

  Write-Host "Uploading: $objectPath"
  $bytes = [System.IO.File]::ReadAllBytes($outputPath)
  Invoke-RestMethod -Uri $uploadUrl -Method Put -Headers $uploadHeaders -Body $bytes -ContentType "video/mp4"

  $publicUrl = "$SUPABASE_URL/storage/v1/object/public/$BUCKET/$objectPath"
  $patchUrl = "$SUPABASE_URL/rest/v1/chat_messages?id=eq.$id"
  $body = @{ media_url_transcoded = $publicUrl } | ConvertTo-Json

  Write-Host "Updating message: $id"
  Invoke-RestMethod -Uri $patchUrl -Method Patch -Headers $headers -ContentType "application/json" -Body $body

  Remove-Item $inputPath -ErrorAction SilentlyContinue
  Remove-Item $outputPath -ErrorAction SilentlyContinue
}

Write-Host "Done."
