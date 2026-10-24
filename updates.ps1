Add-Type -AssemblyName System.Net.Http
$script:installedVersion = [version](Get-Content (Join-Path $PSScriptRoot 'version.txt') -Raw).Trim()
$script:updateStatePath = Join-Path $store 'update-state.json'
$script:updateState = [pscustomobject]@{ next_check_unix = 0; notified_tag = '' }
$script:updateTask = $null
$script:updateNotice = $null
if (Test-Path $script:updateStatePath) {
    try {
        $savedUpdateState = Get-Content $script:updateStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $savedDeadline = 0L
        if ([long]::TryParse([string]$savedUpdateState.next_check_unix, [ref]$savedDeadline) -and $savedDeadline -ge 0) { $script:updateState.next_check_unix = $savedDeadline }
        if ($savedUpdateState.notified_tag -is [string] -and $savedUpdateState.notified_tag -cmatch '^v[0-9]+\.[0-9]+\.[0-9]+\z') { $script:updateState.notified_tag = $savedUpdateState.notified_tag }
    }
    catch [ArgumentException] { Write-Warning 'Invalid update state; the next check will retry.' }
    catch [IO.IOException] { Write-Warning 'Update state is unavailable; the next check will retry.' }
    catch [UnauthorizedAccessException] { Write-Warning 'Update state is not readable; reminders remain active.' }
}
function Get-AvailableUpdate($release, $currentVersion) {
    if ($release.draft -isnot [bool] -or $release.prerelease -isnot [bool]) { return $null }
    if ($release.draft -ne $false -or $release.prerelease -ne $false) { return $null }
    if ($release.tag_name -isnot [string]) { return $null }
    if ($release.tag_name -cnotmatch '^v[0-9]+\.[0-9]+\.[0-9]+\z') { return $null }
    $candidate = $null
    if (-not [version]::TryParse($release.tag_name.Substring(1), [ref]$candidate) -or $candidate -le $currentVersion) { return $null }
    $url = 'https://github.com/AhmedMohamedAbdEllatif/quran-reminder-windows/releases/tag/' + $release.tag_name
    if ($release.html_url -cne $url) { return $null }
    return [pscustomobject]@{ Tag = $release.tag_name; Url = $url }
}
function Save-UpdateState {
    $pendingPath = $script:updateStatePath + '.tmp'
    try {
        [IO.File]::WriteAllText($pendingPath, ($script:updateState | ConvertTo-Json), [Text.Encoding]::UTF8)
        if ([IO.File]::Exists($script:updateStatePath)) { [IO.File]::Replace($pendingPath, $script:updateStatePath, [NullString]::Value) }
        else { [IO.File]::Move($pendingPath, $script:updateStatePath) }
    } catch [IO.IOException] { Write-Warning 'Could not save update status; the next session may notify again.' }
    catch [UnauthorizedAccessException] { Write-Warning 'Update status is not writable; the next session may notify again.' }
}
function New-UpdateNotice($release) {
    [xml]$markup = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Width="440" Height="204"
 WindowStyle="None" ResizeMode="NoResize" AllowsTransparency="True" Background="Transparent"
 Topmost="True" ShowActivated="False" ShowInTaskbar="False" FlowDirection="RightToLeft" Title="تحديث جديد">
 <Border Background="#F4F8F9" BorderBrush="#C7DBE1" BorderThickness="1" CornerRadius="16" Padding="22">
  <StackPanel>
   <TextBlock Text="نسخة جديدة من تذكير القرآن" FontSize="20" FontWeight="SemiBold" Foreground="#193E49"/>
   <TextBlock Name="UpdateVersion" FontSize="15" Foreground="#607D86" Margin="0,10,0,18" TextWrapping="Wrap"/>
   <WrapPanel><Button Name="DownloadUpdate" Content="تحميل التحديث" Background="#24596A" Foreground="White" Margin="0,0,10,0"/>
    <Button Name="CloseUpdate" Content="إغلاق"/></WrapPanel>
  </StackPanel>
 </Border>
</Window>
'@
    $notice = [Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($markup))
    Initialize-WindowStyle $notice
    $notice.FindName('UpdateVersion').Text = 'الإصدار ' + $release.Tag + ' متاح. إعداداتك وتقدمك محفوظان عند التحديث.'
    $notice.FindName('DownloadUpdate').Tag = $release.Url
    $notice.FindName('DownloadUpdate').Add_Click({ param($sender, $eventArgs) Start-Process -FilePath $sender.Tag; [Windows.Window]::GetWindow($sender).Close() })
    $notice.FindName('CloseUpdate').Add_Click({ param($sender, $eventArgs) [Windows.Window]::GetWindow($sender).Close() })
    return $notice
}
function Show-UpdateNotice($release) {
    if ($script:updateNotice) { $script:updateNotice.Close() }
    $script:updateNotice = New-UpdateNotice $release
    $area = [Windows.SystemParameters]::WorkArea
    $script:updateNotice.Width = [Math]::Min(440, $area.Width - 36)
    $script:updateNotice.Left = $area.Right - $script:updateNotice.Width - 18
    $script:updateNotice.Top = $area.Bottom - $script:updateNotice.Height - 18
    $dismissal = [Windows.Threading.DispatcherTimer]::new()
    $dismissal.Interval = [TimeSpan]::FromSeconds(20)
    $dismissal.Tag = $script:updateNotice
    $script:updateNotice.Tag = $dismissal
    $dismissal.Add_Tick({ param($sender, $eventArgs) $sender.Stop(); $sender.Tag.Close() })
    $script:updateNotice.Add_Closed({ param($sender, $eventArgs) $sender.Tag.Stop() })
    $script:updateNotice.Show()
    $dismissal.Start()
}
function Accept-UpdateRelease($release) {
    $available = Get-AvailableUpdate $release $script:installedVersion
    $script:updateState.next_check_unix = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 86400
    if ($available -and $script:updateState.notified_tag -cne $available.Tag) {
        Show-UpdateNotice $available
        $script:updateState.notified_tag = $available.Tag
    }
}
function Complete-UpdateCheck {
    if (-not $script:updateTask.IsCompleted) { return }
    $script:updateCompletionTimer.Stop()
    $script:updateState.next_check_unix = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 3600
    if ($script:updateTask.IsFaulted -or $script:updateTask.IsCanceled) {
        if ($script:updateTask.IsFaulted) { Write-Warning ('Update check unavailable: ' + $script:updateTask.Exception.GetBaseException().GetType().Name) }
        else { Write-Warning 'Update check cancelled; a later check will retry.' }
        Save-UpdateState
        $script:updateTask = $null
        return
    }
    try {
        Accept-UpdateRelease ($script:updateTask.Result | ConvertFrom-Json)
    } catch [ArgumentException] { Write-Warning 'Update response was invalid; a later check will retry.' }
    finally { $script:updateTask = $null }
    Save-UpdateState
}
function Start-UpdateCheck {
    if ($script:updateTask) { return }
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if ($script:updateState.next_check_unix -gt $now -and $script:updateState.next_check_unix -le $now + 86400) { return }
    $script:updateTask = $script:updateHttpClient.GetStringAsync('https://api.github.com/repos/AhmedMohamedAbdEllatif/quran-reminder-windows/releases/latest')
    $script:updateCompletionTimer.Start()
}
function Start-UpdateChecks {
    $script:updateHttpClient = [Net.Http.HttpClient]::new()
    $script:updateHttpClient.Timeout = [TimeSpan]::FromSeconds(10)
    $script:updateHttpClient.MaxResponseContentBufferSize = 262144
    $script:updateHttpClient.DefaultRequestHeaders.UserAgent.ParseAdd('QuranReminder/' + $script:installedVersion.ToString())
    $script:updateHttpClient.DefaultRequestHeaders.Accept.ParseAdd('application/vnd.github+json')
    $script:updateCompletionTimer = [Windows.Threading.DispatcherTimer]::new()
    $script:updateCompletionTimer.Interval = [TimeSpan]::FromSeconds(1)
    $script:updateCompletionTimer.Add_Tick({ Complete-UpdateCheck })
    $script:updateCheckTimer = [Windows.Threading.DispatcherTimer]::new()
    $script:updateCheckTimer.Interval = [TimeSpan]::FromSeconds(20)
    $script:updateCheckTimer.Add_Tick({ $script:updateCheckTimer.Interval = [TimeSpan]::FromMinutes(15); Start-UpdateCheck })
    $script:updateCheckTimer.Start()
}
function Stop-UpdateChecks {
    if ($script:updateCheckTimer) { $script:updateCheckTimer.Stop() }
    if ($script:updateCompletionTimer) { $script:updateCompletionTimer.Stop() }
    if ($script:updateHttpClient) { $script:updateHttpClient.Dispose() }
}
