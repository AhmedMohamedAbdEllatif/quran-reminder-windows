$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
$installFolder = Join-Path $env:LOCALAPPDATA 'QuranReminder\App'
$requiredFiles = @('reminder.ps1', 'settings.ps1', 'tafsir.ps1', 'ui.ps1', 'ui.xaml', 'config.json', 'verses.json', 'background.png', 'Start.vbs', 'README.txt')
try {
    foreach ($fileName in $requiredFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $fileName) -PathType Leaf)) { throw ('Missing file: ' + $fileName) }
    }
    [IO.Directory]::CreateDirectory($installFolder) | Out-Null
    foreach ($fileName in $requiredFiles) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $fileName) -Destination (Join-Path $installFolder $fileName) -Force
    }
    $startupFolder = [Environment]::GetFolderPath([Environment+SpecialFolder]::Startup)
    $shortcutPath = Join-Path $startupFolder 'Quran Reminder.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
    $shortcut.Arguments = '"' + (Join-Path $installFolder 'Start.vbs') + '"'
    $shortcut.WorkingDirectory = $installFolder
    $shortcut.WindowStyle = 7
    $shortcut.Description = 'تذكير القرآن — تشغيل تلقائي عند تسجيل الدخول'
    $shortcut.Save()
    Start-Process -FilePath $shortcut.TargetPath -ArgumentList $shortcut.Arguments -WindowStyle Hidden
    [Windows.MessageBox]::Show('تم التثبيت. البرنامج سيعمل تلقائيًا كل مرة تدخل فيها إلى ويندوز، ولا تحتاج لفتح أي ملف مرة أخرى.', 'تذكير القرآن') | Out-Null
} catch {
    [Windows.MessageBox]::Show($_.Exception.Message, 'تعذر تثبيت تذكير القرآن') | Out-Null
    exit 1
}
