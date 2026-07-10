$port = 19000
$url = "http://127.0.0.1:$port/"
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($url)
try {
    $listener.Start()
} catch {
    Write-Host "Failed to start listener. Please run as Administrator."
    Pause
    exit
}

Write-Host "TgNAS Setup Wizard running at $url"
Start-Process $url

while ($listener.IsListening) {
    $context = $listener.GetContext()
    $request = $context.Request
    $response = $context.Response

    # CORS Headers
    $response.AddHeader("Access-Control-Allow-Origin", "*")
    $response.AddHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS")

    if ($request.HttpMethod -eq 'OPTIONS') {
        $response.Close()
        continue
    }

    if ($request.HttpMethod -eq 'GET' -and ($request.Url.AbsolutePath -eq '/' -or $request.Url.AbsolutePath -eq '/index.html')) {
        $htmlPath = Join-Path $PSScriptRoot "index.html"
        $html = Get-Content -Raw -Path $htmlPath -Encoding UTF8
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($html)
        $response.ContentLength64 = $buffer.Length
        $response.ContentType = "text/html; charset=utf-8"
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
        $response.Close()
    }
    elseif ($request.HttpMethod -eq 'POST' -and $request.Url.AbsolutePath -eq '/api/deploy') {
        $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
        $json = $reader.ReadToEnd()
        $data = $json | ConvertFrom-Json

        Write-Host "Received config. Deploying..."
        
        $rootPath = (Get-Item $PSScriptRoot).Parent.FullName

        # Generate tgnas/.env
        $envContent = @"
TGNAS_SECRET_KEY=$($data.s3Secret)
TGNAS_TELEGRAM_BOT_TOKEN=$($data.botToken)
TGNAS_TELEGRAM_CHAT_ID=$($data.chatId)

HTTP_PROXY=$($data.httpProxy)
HTTPS_PROXY=$($data.httpProxy)
TGNAS_PORT_EXPOSED=9000
"@
        Set-Content -Path (Join-Path $rootPath "tgnas\.env") -Value $envContent -Encoding UTF8

        # Generate telegram-bot-api/.env
        $botEnvContent = @"
TELEGRAM_API_ID=$($data.apiId)
TELEGRAM_API_HASH=$($data.apiHash)
"@
        Set-Content -Path (Join-Path $rootPath "telegram-bot-api\.env") -Value $botEnvContent -Encoding UTF8

        # Run docker-compose
        Write-Host "Starting telegram-bot-api..."
        Set-Location (Join-Path $rootPath "telegram-bot-api")
        docker compose up -d

        Write-Host "Starting tgnas..."
        Set-Location (Join-Path $rootPath "tgnas")
        docker compose up -d
        
        Set-Location $rootPath

        $resString = '{"status":"success"}'
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($resString)
        $response.ContentLength64 = $buffer.Length
        $response.ContentType = "application/json; charset=utf-8"
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
        $response.Close()
        
        Write-Host "Deployment completed! Shutting down wizard server..."
        $listener.Stop()
    }
    else {
        $response.StatusCode = 404
        $response.Close()
    }
}
