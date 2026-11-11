#requires -Version 7.4
Set-StrictMode -Version Latest

function Read-ConnectConfig([string]$Path) {
    $c = @{ proxyMode='auto'; proxyUrl=''; appPath=''; timeoutSeconds=10; codexConfigPath='' }
    if ($Path -and (Test-Path -LiteralPath $Path)) {
        $inputConfig = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
        foreach ($key in $inputConfig.Keys) {
            if (-not $c.ContainsKey($key)) { throw "Unknown config option: $key" }
            $c[$key] = $inputConfig[$key]
        }
    }
    if ($c.proxyMode -notin @('auto','explicit','direct')) { throw 'proxyMode must be auto, explicit or direct.' }
    if ($c.timeoutSeconds -isnot [long] -and $c.timeoutSeconds -isnot [int]) { throw 'timeoutSeconds must be an integer.' }
    if ($c.timeoutSeconds -lt 1 -or $c.timeoutSeconds -gt 60) { throw 'timeoutSeconds must be between 1 and 60.' }
    return $c
}

function Test-ProxyUrl([string]$Url) {
    $uri = $null
    if (-not [Uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -notin @('http','https') -or
        $uri.UserInfo -or $uri.AbsolutePath -ne '/' -or $uri.Query -or $uri.Fragment) {
        throw 'Use an HTTP/HTTPS proxy URL without credentials, path or query; for example http://127.0.0.1:7897.'
    }
    return $Url.TrimEnd('/')
}

function Resolve-ConnectProxy([hashtable]$Config) {
    if ($Config.proxyMode -eq 'direct') { return '' }
    if ($Config.proxyMode -eq 'explicit') { return Test-ProxyUrl $Config.proxyUrl }
    if ($IsWindows) {
        $settings = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
        if ($settings -and $settings.PSObject.Properties['ProxyEnable'] -and $settings.ProxyEnable -eq 1) {
            $server = [string]$settings.ProxyServer
            if ($server -match '(?:^|;)https=([^;]+)') { $server = $Matches[1] }
            elseif ($server -match '(?:^|;)http=([^;]+)') { $server = $Matches[1] }
            elseif ($server.Contains('=')) { throw 'Cannot resolve this system proxy format. Set proxyMode=explicit.' }
            if ($server -notmatch '^https?://') { $server = 'http://' + $server }
            return Test-ProxyUrl $server
        }
        if ($settings -and $settings.PSObject.Properties['AutoConfigURL'] -and $settings.AutoConfigURL) {
            throw 'PAC is configured. Resolve its HTTP proxy address and use explicit mode; PAC is not evaluated here.'
        }
    }
    foreach ($name in @('HTTPS_PROXY','HTTP_PROXY')) {
        $value = [Environment]::GetEnvironmentVariable($name)
        if ($value) { return Test-ProxyUrl $value }
    }
    return ''
}

function Test-ConnectEndpoint([string]$Url, [string]$Proxy, [int]$TimeoutSeconds=10) {
    $uri = [Uri]$Url
    if ($uri.Scheme -ne 'https' -or $uri.UserInfo -or $uri.Query) { throw 'Diagnostics require an HTTPS URL without credentials or query.' }
    $curl = (Get-Command curl.exe -ErrorAction Stop).Source
    $psi = [Diagnostics.ProcessStartInfo]::new($curl)
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $argsList = @('--silent','--show-error','--output','NUL','--connect-timeout',"$TimeoutSeconds",'--max-time',"$TimeoutSeconds",'--write-out','%{http_code}|%{time_appconnect}|%{time_total}')
    # Override both inherited proxy and NO_PROXY so the selected route is actually tested.
    if ($Proxy) { $argsList += @('--proxy',$Proxy,'--noproxy','') }
    else { $argsList += @('--noproxy','*') }
    $argsList += $Url
    foreach ($arg in $argsList) { $psi.ArgumentList.Add($arg) }
    $p = [Diagnostics.Process]::Start($psi)
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit(($TimeoutSeconds+5)*1000)) { $p.Kill($true); throw 'curl exceeded the diagnostic time limit.' }
    $parts = $outTask.GetAwaiter().GetResult().Trim().Split('|')
    $null = $errTask.GetAwaiter().GetResult() # Never export raw curl error text or server response bodies.
    $code = 0; $tls = 0.0; $total = 0.0
    if ($parts.Count -eq 3) {
        $code = [int]$parts[0]
        $tls = [double]::Parse($parts[1], [Globalization.CultureInfo]::InvariantCulture)
        $total = [double]::Parse($parts[2], [Globalization.CultureInfo]::InvariantCulture)
    }
    $category = if ($p.ExitCode -ne 0) { 'transport_error' } elseif ($code -in 401,403) { 'auth_or_policy_required' } elseif ($code -ge 500 -or $code -eq 429) { 'server_or_rate_limit' } else { 'http_response' }
    $result = [pscustomobject]@{ host=$uri.DnsSafeHost; httpStatus=$code; curlExitCode=$p.ExitCode; tlsSeconds=$tls; totalSeconds=$total; category=$category; transportReachable=($p.ExitCode -eq 0 -and $code -gt 0); authenticatedSessionVerified=$false; websocketVerified=$false }
    $p.Dispose()
    return $result
}

function Get-CodexConfigPath([hashtable]$Config) {
    if ($Config.codexConfigPath) { return [IO.Path]::GetFullPath($Config.codexConfigPath) }
    $codexDir = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex' }
    return Join-Path $codexDir 'config.toml'
}

function Update-ProxyFeatureText([string]$Text) {
    # Conservative line editor, NOT a general TOML parser. Refuse ambiguous forms rather than rewrite unrelated config.
    if ($Text.Contains('"""') -or $Text.Contains("'''")) { throw 'Multiline TOML strings require a manual edit.' }
    if ($Text -match '(?m)^\s*features\s*\.') { throw 'Dotted features keys require a manual edit.' }
    if ($Text -match '(?m)^\s*\[\s+features\s*\]' -or $Text -match '(?m)^\s*\[features\s+\]') { throw 'Noncanonical features table requires a manual edit.' }
    if ($Text -match '(?m)^\s*features\s*=' -or $Text -match '(?m)^\s*\[\s*["'']features') { throw 'Inline or quoted features tables require a manual edit.' }
    $heads = [regex]::Matches($Text, '(?m)^\s*\[features\][ \t]*(?:#[^\r\n]*)?\r?$')
    if ($heads.Count -gt 1) { throw 'Duplicate [features] tables; repair TOML manually.' }
    $nl = if ($Text.Contains("`r`n")) { "`r`n" } else { "`n" }
    if ($heads.Count -eq 0) {
        if ($Text -match '(?m)^\s*\[\[features\]\]') { throw 'Array features tables are unsupported.' }
        return $Text.TrimEnd("`r","`n") + $nl + $nl + '[features]' + $nl + 'respect_system_proxy = true' + $nl
    }
    $start = $heads[0].Index + $heads[0].Length
    $rest = $Text.Substring($start)
    $next = [regex]::Match($rest, '(?m)^\s*\[')
    $end = if ($next.Success) { $start + $next.Index } else { $Text.Length }
    $body = $Text.Substring($start, $end-$start)
    $keys = [regex]::Matches($body, '(?m)^[ \t]*respect_system_proxy[ \t]*=[^\r\n]*')
    if ($keys.Count -gt 1) { throw 'Duplicate respect_system_proxy keys.' }
    if ($body -match '(?m)^\s*["'']respect_system_proxy') { throw 'Quoted feature key requires a manual edit.' }
    if ($keys.Count -eq 1) {
        if ($keys[0].Value -notmatch '=\s*(true|false)\s*(?:#.*)?$') { throw 'Unsupported proxy feature value.' }
        $newBody = [regex]::Replace($body, '(?m)^([ \t]*respect_system_proxy[ \t]*=[ \t]*)(true|false)', '${1}true')
    } else { $newBody = $nl + 'respect_system_proxy = true' + $nl + $body.TrimStart("`r","`n") }
    return $Text.Substring(0,$start) + $newBody + $Text.Substring($end)
}

function Enable-CodexSystemProxy([string]$Path, [string]$DataDir) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'config.toml was not found. Create it manually using docs/CONFIGURATION.md first.' }
    $beforeHash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    $text = [IO.File]::ReadAllText($Path)
    $updated = Update-ProxyFeatureText $text
    if ($updated -eq $text) { return 'Already enabled; no file changed.' }
    New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
    $backup = Join-Path $DataDir ('config-' + [Guid]::NewGuid().ToString('N') + '.bak')
    Copy-Item -LiteralPath $Path -Destination $backup
    if ((Get-FileHash -LiteralPath $Path).Hash -ne $beforeHash) { throw 'Config changed during backup. Nothing written.' }
    [IO.File]::WriteAllText($Path, $updated, [Text.UTF8Encoding]::new($false))
    @{ path=$Path; backup=$backup; appliedHash=(Get-FileHash -LiteralPath $Path).Hash } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $DataDir 'last-config-change.json') -Encoding utf8
    return 'Enabled respect_system_proxy. Restart the desktop app to load the setting.'
}

function Restore-CodexSystemProxy([string]$Path, [string]$DataDir) {
    $state = Get-Content -LiteralPath (Join-Path $DataDir 'last-config-change.json') -Raw | ConvertFrom-Json
    if ([IO.Path]::GetFullPath($Path) -ne [IO.Path]::GetFullPath($state.path)) { throw 'Backup belongs to a different config file.' }
    if ((Get-FileHash -LiteralPath $Path).Hash -ne $state.appliedHash) { throw 'Config changed since repair. Restore refused to preserve later edits.' }
    Copy-Item -LiteralPath $state.backup -Destination $Path -Force
    return 'Original config restored.'
}

function Get-ConnectAppPath([hashtable]$Config) {
    if ($Config.appPath) { $path = [IO.Path]::GetFullPath($Config.appPath) }
    else {
        $package = Get-AppxPackage OpenAI.Codex | Sort-Object Version -Descending | Select-Object -First 1
        if (-not $package) { throw 'ChatGPT desktop package not found; set appPath in config.local.json.' }
        $path = Join-Path $package.InstallLocation 'app\ChatGPT.exe'
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or [IO.Path]::GetExtension($path) -ne '.exe') { throw 'appPath must point to an installed executable.' }
    return $path
}

Export-ModuleMember -Function *-*
