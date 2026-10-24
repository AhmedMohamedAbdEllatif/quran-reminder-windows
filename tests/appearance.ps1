function Export-WindowPreview($targetWindow, $destination) {
    $targetWindow.Show()
    $targetWindow.UpdateLayout()
    $bitmap = [Windows.Media.Imaging.RenderTargetBitmap]::new([int]$targetWindow.ActualWidth, [int]$targetWindow.ActualHeight, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($targetWindow)
    $encoder = [Windows.Media.Imaging.PngBitmapEncoder]::new()
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream = [IO.File]::Create($destination)
    try { $encoder.Save($stream) } finally { $stream.Dispose() }
}
function Test-ReminderAppearance($destination) {
    [IO.Directory]::CreateDirectory($destination) | Out-Null
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
    if ($window.Height -gt [Windows.SystemParameters]::WorkArea.Height - 32) { throw 'Long verse exceeded available screen height.' }
    Hide-Verse
    $timer.Stop()
}
