param([switch]$Check)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
$installFolder = Join-Path $env:LOCALAPPDATA 'QuranReminder\App'
$requiredFiles = @('reminder.ps1', 'settings.ps1', 'tafsir.ps1', 'memorization.ps1', 'mushaf-lines.json', 'tanzil-uthmani-1.1.txt', 'THIRD_PARTY_NOTICES.md', 'ui.ps1', 'ui.xaml', 'config.json', 'verses.json', 'background.png', 'Start.vbs', 'README.txt')
function Copy-ApplicationFile($sourcePath, $destinationPath) {
    $pendingPath = $destinationPath + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    [IO.File]::Copy($sourcePath, $pendingPath)
    if ([IO.File]::Exists($destinationPath)) { [IO.File]::Replace($pendingPath, $destinationPath, [NullString]::Value) }
    else { [IO.File]::Move($pendingPath, $destinationPath) }
}
function Copy-ApplicationFiles($sourceFolder, $destinationFolder) {
    foreach ($fileName in $requiredFiles) {
        $sourcePath = Join-Path $sourceFolder $fileName
        if (-not [IO.File]::Exists($sourcePath)) { throw [IO.FileNotFoundException]::new(('ملف التثبيت غير موجود: ' + $fileName), $sourcePath) }
    }
    $installedScript = Join-Path $destinationFolder 'reminder.ps1'
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -and $_.CommandLine.IndexOf($installedScript, [StringComparison]::OrdinalIgnoreCase) -ge 0 } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
    [IO.Directory]::CreateDirectory($destinationFolder) | Out-Null
    foreach ($fileName in $requiredFiles) {
        $destinationPath = Join-Path $destinationFolder $fileName
        if ($fileName -eq 'config.json' -and [IO.File]::Exists($destinationPath)) { continue }
        Copy-ApplicationFile (Join-Path $sourceFolder $fileName) $destinationPath
    }
}
function Set-StartupShortcut($applicationFolder, $startupFolder) {
    $shortcutPath = Join-Path $startupFolder 'Quran Reminder.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
    $shortcut.Arguments = '"' + (Join-Path $applicationFolder 'Start.vbs') + '"'
    $shortcut.WorkingDirectory = $applicationFolder
    $shortcut.WindowStyle = 7
    $shortcut.Description = 'تذكير القرآن — تشغيل تلقائي عند تسجيل الدخول'
    $shortcut.Save()
}
if ($Check) {
    $testRoot = Join-Path ([IO.Path]::GetTempPath()) ('QuranInstall-Check-' + [Guid]::NewGuid().ToString('N'))
    $testApp = Join-Path $testRoot 'App'
    Copy-ApplicationFiles $PSScriptRoot $testApp
    $testConfigPath = Join-Path $testApp 'config.json'
    [IO.File]::WriteAllText($testConfigPath, '{"interval_seconds":600,"font_size":40,"auto_hide_seconds":0}')
    $testProgressPath = Join-Path $testRoot 'progress.json'
    [IO.File]::WriteAllText($testProgressPath, '{"read_count":17,"current_index":25}')
    Copy-ApplicationFiles $PSScriptRoot $testApp
    $preservedConfig = Get-Content $testConfigPath -Raw | ConvertFrom-Json
    if ($preservedConfig.interval_seconds -ne 600 -or $preservedConfig.font_size -ne 40) { throw 'Update replaced customized configuration.' }
    if ((Get-Content $testProgressPath -Raw | ConvertFrom-Json).current_index -ne 25) { throw 'Update replaced reading progress.' }
    Set-StartupShortcut $testApp $testRoot
    $testShell = New-Object -ComObject WScript.Shell
    $testShortcut = $testShell.CreateShortcut((Join-Path $testRoot 'Quran Reminder.lnk'))
    if ($testShortcut.Arguments -ne ('"' + (Join-Path $testApp 'Start.vbs') + '"')) { throw 'Automatic startup shortcut targets the wrong application.' }
    try { Copy-ApplicationFiles $testRoot $testApp; throw 'Incomplete installation package was accepted.' }
    catch [IO.FileNotFoundException] { }
    'Installer checks passed: repeat installation, preserved configuration/progress, startup shortcut, missing package.'
    exit
}
try {
    Copy-ApplicationFiles $PSScriptRoot $installFolder
    $startupFolder = [Environment]::GetFolderPath([Environment+SpecialFolder]::Startup)
    Set-StartupShortcut $installFolder $startupFolder
    $launcher = Join-Path $env:WINDIR 'System32\wscript.exe'
    $launchArguments = '"' + (Join-Path $installFolder 'Start.vbs') + '"'
    Start-Process -FilePath $launcher -ArgumentList $launchArguments -WindowStyle Hidden
    [Windows.MessageBox]::Show('تم التثبيت. البرنامج سيعمل تلقائيًا كل مرة تدخل فيها إلى ويندوز، ولا تحتاج لفتح أي ملف مرة أخرى.', 'تذكير القرآن') | Out-Null
} catch {
    [Windows.MessageBox]::Show($_.Exception.Message, 'تعذر تثبيت تذكير القرآن') | Out-Null
    exit 1
}

