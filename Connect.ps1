#requires -Version 7.4
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Diagnose','Launch','EnableCodexProxy','RestoreCodexProxy','InstallShortcut')][string]$Action='Diagnose',
    [string]$ConfigPath=(Join-Path $PSScriptRoot 'config.local.json')
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'src/Connect.Core.psm1') -Force
$config=Read-ConnectConfig $ConfigPath
$data=Join-Path $PSScriptRoot 'data'
if (-not $IsWindows) { throw 'This release supports Windows only.' }
switch ($Action) {
    'Diagnose' {
        $proxy=Resolve-ConnectProxy $config
        Write-Host ('Route: ' + $(if ($proxy) {'explicit HTTP proxy'} else {'direct / system VPN routing'}))
        $endpoints=@('https://chatgpt.com/backend-api/wham/remote/control/server','https://codex-cloud-backend.chatgpt.com/','https://codex-cloud-environments.chatgpt.com/api')
        $results=@(foreach ($url in $endpoints) { Test-ConnectEndpoint $url $proxy $config.timeoutSeconds })
        New-Item -ItemType Directory -Path $data -Force | Out-Null
        @{ timestamp=[DateTimeOffset]::Now.ToString('o'); route=$(if($proxy){'proxy'}else{'direct'}); endpoints=$results; dotReadVerified=$false } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $data 'diagnostics.json')
        $results | Format-Table host,httpStatus,curlExitCode,totalSeconds,category
        Write-Host 'This checks TLS/HTTP only. It does not verify authenticated WebSockets or Dot file access.'
        if (@($results | Where-Object { -not $_.transportReachable }).Count) { exit 2 }
    }
    'EnableCodexProxy' {
        $path=Get-CodexConfigPath $config
        if ($PSCmdlet.ShouldProcess($path,'Enable [features].respect_system_proxy with backup')) { Enable-CodexSystemProxy $path $data }
    }
    'RestoreCodexProxy' {
        $path=Get-CodexConfigPath $config
        if ($PSCmdlet.ShouldProcess($path,'Restore previous config if unchanged since repair')) { Restore-CodexSystemProxy $path $data }
    }
    'Launch' {
        $exe=Get-ConnectAppPath $config
        $proxy=Resolve-ConnectProxy $config
        $existing=Get-CimInstance Win32_Process -Filter "Name='ChatGPT.exe'" | Where-Object { $_.ExecutablePath -eq $exe -and $_.CommandLine -notmatch '--type=' } | Select-Object -First 1
        if ($existing) {
            Write-Host 'The app is already running. Opening it now. To load new proxy settings, fully exit the app and launch again.'
            if ($PSCmdlet.ShouldProcess($exe,'Open existing app')) { Start-Process -FilePath $exe }
            return
        }
        if (-not $PSCmdlet.ShouldProcess($exe,'Launch once with process-scoped proxy settings')) { return }
        $names=@('HTTP_PROXY','HTTPS_PROXY','ALL_PROXY','NO_PROXY','NODE_USE_ENV_PROXY')
        $saved=@{}; foreach($name in $names){$saved[$name]=[Environment]::GetEnvironmentVariable($name)}
        try {
            foreach($name in @('HTTP_PROXY','HTTPS_PROXY','ALL_PROXY')) { [Environment]::SetEnvironmentVariable($name,$proxy,'Process') }
            $env:NO_PROXY='localhost,127.0.0.1,::1'
            $env:NODE_USE_ENV_PROXY= $(if($proxy){'1'}else{'0'})
            if ($proxy) { Start-Process -FilePath $exe -ArgumentList "--proxy-server=$proxy" }
            else { Start-Process -FilePath $exe -ArgumentList '--no-proxy-server' }
            Write-Host 'Launch requested. Verify Dot access using docs/VERIFICATION.md; process startup is not connection success.'
        } finally { foreach($name in $names){[Environment]::SetEnvironmentVariable($name,$saved[$name],'Process')} }
    }
    'InstallShortcut' {
        $target=Join-Path $PSHOME 'pwsh.exe'
        $linkPath=Join-Path ([Environment]::GetFolderPath('Desktop')) 'dot ChatGPT.lnk'
        if ($PSCmdlet.ShouldProcess($linkPath,'Create or update desktop shortcut')) {
            $shell=New-Object -ComObject WScript.Shell
            $link=$shell.CreateShortcut($linkPath)
            $link.TargetPath=$target
            $entry=Join-Path $PSScriptRoot 'Connect.ps1'
            $link.Arguments='-NoLogo -NoProfile -File "'+$entry+'" -Action Launch -ConfigPath "'+[IO.Path]::GetFullPath($ConfigPath)+'"'
            $link.WorkingDirectory=$PSScriptRoot
            $link.IconLocation=(Join-Path $PSScriptRoot 'assets/dot.ico')+',0'
            $link.Save()
            Write-Host 'Desktop shortcut installed. Keep this folder in its current location.'
        }
    }
}
