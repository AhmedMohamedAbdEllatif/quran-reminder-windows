function Export-WindowPreview($targetWindow, $destination) {
    $targetWindow.Show()
    $targetWindow.UpdateLayout()
    $bitmap = [Windows.Media.Imaging.RenderTargetBitmap]::new([int]$targetWindow.Content.ActualWidth, [int]$targetWindow.Content.ActualHeight, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($targetWindow)
    $encoder = [Windows.Media.Imaging.PngBitmapEncoder]::new()
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream = [IO.File]::Create($destination)
    try { $encoder.Save($stream) } finally { $stream.Dispose() }
}
function Test-ReminderAppearance($destination) {
    [IO.Directory]::CreateDirectory($destination) | Out-Null
    Reset-DefaultBackground
    Set-VersesPerReminder 3
    Set-StartingVerse 0
    Show-Verse
    Export-WindowPreview $window (Join-Path $destination 'reading-group.png')
    Set-VersesPerReminder 1
    Set-StartingVerse 288
    Show-Verse
    Export-WindowPreview $window (Join-Path $destination 'long-verse.png')
    $settingsPreview = New-SettingsWindow
    $settingsPreview.Width = 480
    $settingsPreview.Height = 640
    $settingsPreview.FindName('ReadingInterval').Text = '5'
    $settingsPreview.FindName('VerseCount').Items.Add([pscustomobject]@{Label='3 آيات';Count=3}) | Out-Null
    $settingsPreview.FindName('VerseCount').SelectedIndex = 0
    $settingsPreview.FindName('ShowTranslation').IsChecked = $true
    Export-WindowPreview $settingsPreview (Join-Path $destination 'settings-small.png')
    $settingsPreview.Close()
    $updatePreview = New-UpdateNotice ([pscustomobject]@{Tag='v1.7.0';Url='https://github.com/AhmedMohamedAbdEllatif/quran-reminder-windows/releases/tag/v1.7.0'})
    Export-WindowPreview $updatePreview (Join-Path $destination 'update-notice.png')
    $updatePreview.Close()
    $previewPlan = Get-MemorizationCopy
    $previewPlan.page = 308; $previewPlan.lines_per_part = 5; $previewPlan.part_index = 0; $previewPlan.confirmed_repeats = 0; $previewPlan.enabled = $false
    Save-Memorization $previewPlan
    Show-Memorization
    Export-WindowPreview $script:memorizationWindow (Join-Path $destination 'memorization-default.png')
    Set-CustomBackground (Join-Path (Split-Path -Parent $PSScriptRoot) 'background.png')
    Export-WindowPreview $script:memorizationWindow (Join-Path $destination 'memorization-custom.png')
    Set-StartingVerse 0
    Set-VersesPerReminder 3
    Show-Verse
    Export-WindowPreview $window (Join-Path $destination 'reading-custom.png')
    Reset-DefaultBackground
    Hide-Memorization
    if ($window.Height -gt [Windows.SystemParameters]::WorkArea.Height - 32) { throw 'Long verse exceeded available screen height.' }
    Hide-Verse
    $timer.Stop()
}
