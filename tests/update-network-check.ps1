$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
$applicationRoot = Split-Path -Parent $PSScriptRoot
$store = Join-Path ([IO.Path]::GetTempPath()) ('QuranUpdate-Network-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($store) | Out-Null
. (Join-Path $applicationRoot 'ui.ps1')
. (Join-Path $applicationRoot 'updates.ps1')
Start-UpdateChecks
$script:updateCheckTimer.Stop()
Start-UpdateCheck
$networkFrame = [Windows.Threading.DispatcherFrame]::new()
$heartbeatCount = 0
$heartbeat = [Windows.Threading.DispatcherTimer]::new()
$heartbeat.Interval = [TimeSpan]::FromMilliseconds(50)
$heartbeat.Add_Tick({
    $script:heartbeatCount++
    if (-not $script:updateTask) { $heartbeat.Stop(); $networkFrame.Continue = $false }
})
$heartbeat.Start()
[Windows.Threading.Dispatcher]::PushFrame($networkFrame)
Stop-UpdateChecks
if ($script:updateNotice) { $script:updateNotice.Close() }
if ($heartbeatCount -lt 2) { throw 'The UI dispatcher did not run while checking the network.' }
if ($script:updateState.next_check_unix -lt [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 80000) { throw 'Live GitHub check failed; retry was scheduled without interrupting reminders.' }
'Live GitHub check passed; UI dispatcher stayed responsive; no credentials required.'
