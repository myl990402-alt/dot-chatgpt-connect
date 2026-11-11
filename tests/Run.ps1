#requires -Version 7.4
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '../src/Connect.Core.psm1') -Force -DisableNameChecking
$count=0
function Assert($Condition, [string]$Message) { if(-not $Condition){throw $Message}; $script:count++ }
function Assert-Throws([scriptblock]$Code,[string]$Message){$threw=$false;try{& $Code | Out-Null}catch{$threw=$true};Assert $threw $Message}
$text="model = `"example`"`r`n[features]`r`nrespect_system_proxy = false # keep`r`nother = true`r`n[projects.sample]`r`ntrust_level = `"trusted`"`r`n"
$updated=Update-ProxyFeatureText $text
Assert ($updated -ceq $text.Replace('respect_system_proxy = false','respect_system_proxy = true')) 'Only the intended feature may change; comments and CRLF must survive.'
Assert ((Update-ProxyFeatureText $updated) -ceq $updated) 'Applying twice must be idempotent.'
$absent="[features]`nother = true`n[next]`nvalue = 1`n"
$inserted=Update-ProxyFeatureText $absent
Assert ($inserted.IndexOf('respect_system_proxy') -lt $inserted.IndexOf('[next]')) 'Inserted setting must belong to features.'
Assert ((Update-ProxyFeatureText 'model = "test"') -match '(?m)^\[features\]$') 'Missing table must be added.'
Assert-Throws {Update-ProxyFeatureText "[features]`nrespect_system_proxy = true`nrespect_system_proxy = false"} 'Duplicate feature keys must be rejected.'
Assert-Throws {Update-ProxyFeatureText "[features]`n[features]"} 'Duplicate tables must be rejected.'
Assert-Throws {Update-ProxyFeatureText 'features = { other = true }'} 'Inline table must not be overwritten.'
Assert-Throws {Update-ProxyFeatureText 'text = """x"""'} 'Multiline strings must not be edited as tables.'
Assert-Throws {Update-ProxyFeatureText 'features.respect_system_proxy = false'} 'Dotted keys must not create duplicate features.'
Assert-Throws {Update-ProxyFeatureText '[ features ]'} 'Unsupported table spacing must not create duplicate tables.'
Assert ((Test-ProxyUrl 'http://127.0.0.1:7897/') -eq 'http://127.0.0.1:7897') 'Local proxy URL should normalize.'
foreach($bad in @('http://user:secret@localhost:7897','http://localhost/path','socks5://localhost:7897','http://localhost/?token=x')) { Assert-Throws {Test-ProxyUrl $bad} 'Credential-bearing or unsupported proxy URL must fail.' }
Assert ((Resolve-ConnectProxy @{proxyMode='direct'}) -eq '') 'Direct mode must override inherited proxy.'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('dot-connect-test-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    $path=Join-Path $temp 'config.toml'
    [IO.File]::WriteAllText($path,$text)
    $data=Join-Path $temp 'private'
    Enable-CodexSystemProxy $path $data | Out-Null
    Assert ([IO.File]::ReadAllText($path) -ceq $updated) 'Actual file edit should match the planned edit.'
    Restore-CodexSystemProxy $path $data | Out-Null
    Assert ([IO.File]::ReadAllText($path) -ceq $text) 'Restore must recover exact original bytes for this UTF8 fixture.'
    Enable-CodexSystemProxy $path $data | Out-Null
    Add-Content $path '# later user edit'
    Assert-Throws {Restore-CodexSystemProxy $path $data} 'Rollback must refuse to overwrite newer user edits.'
    $cfg=Join-Path $temp 'bad.json'
    '{"timeoutSeconds":0}' | Set-Content $cfg
    Assert-Throws {Read-ConnectConfig $cfg} 'Invalid time limit must fail.'
    '{"unknownOption":true}' | Set-Content $cfg
    Assert-Throws {Read-ConnectConfig $cfg} 'Unknown option must fail.'
} finally {
    # Only delete the exact directory created by this test in the OS temp folder.
    $resolved=[IO.Path]::GetFullPath($temp)
    $root=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if($resolved.StartsWith($root,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf).StartsWith('dot-connect-test-')) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
Write-Host "PASS: $count assertions (offline; no real user configuration or app changed)."
