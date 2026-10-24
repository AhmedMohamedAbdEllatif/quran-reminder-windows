param([switch]$Check)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing
. (Join-Path $PSScriptRoot 'ui.ps1')
$store = Join-Path $env:LOCALAPPDATA 'QuranReminder'
if ($Check) { $store = Join-Path ([IO.Path]::GetTempPath()) ('QuranReminder-Check-' + [Guid]::NewGuid().ToString('N')) }
[IO.Directory]::CreateDirectory($store) | Out-Null
$statePath = Join-Path $store 'progress.json'
$preferencesPath = Join-Path $store 'preferences.json'
$script:versesPerReminder = 1
$script:showTranslation = $true
if (Test-Path $preferencesPath) {
    $preferences = Get-Content $preferencesPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $script:versesPerReminder = [int]$preferences.verses_per_reminder
    if ($script:versesPerReminder -lt 1 -or $script:versesPerReminder -gt 20) { throw 'Invalid verses per reminder.' }
    if ($null -ne $preferences.show_translation) {
        if ($preferences.show_translation -isnot [bool]) { throw 'Invalid translation preference.' }
        $script:showTranslation = $preferences.show_translation
    }
}
$config = Get-Content (Join-Path $PSScriptRoot 'config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$verses = (Get-Content (Join-Path $PSScriptRoot 'verses.json') -Raw -Encoding UTF8 | ConvertFrom-Json).verses
if ($verses.Count -ne 6236) { throw 'Incomplete Quran dataset.' }
foreach ($verse in $verses) {
    if ([string]::IsNullOrWhiteSpace($verse.english)) { throw 'Missing English translation.' }
    if ([string]::IsNullOrWhiteSpace($verse.tafsir)) { throw 'Missing Arabic tafsir.' }
}
$script:readingIntervalSeconds = 300
if ($config.interval_seconds -ge 10) { $script:readingIntervalSeconds = [int]$config.interval_seconds }
if ($null -ne $preferences -and $null -ne $preferences.reading_interval_seconds) {
    if ($preferences.reading_interval_seconds -lt 10 -or $preferences.reading_interval_seconds -gt 86400) { throw 'Invalid reading interval.' }
    $script:readingIntervalSeconds = [int]$preferences.reading_interval_seconds
}
$fontSize = [Math]::Min(64, [Math]::Max(18, [int]$config.font_size))
$script:readCount = 0
$script:currentIndex = 0
if (Test-Path $statePath) {
    $savedProgress = Get-Content $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $script:readCount = [int]$savedProgress.read_count
    $script:currentIndex = $script:readCount
    if ($null -ne $savedProgress.current_index) { $script:currentIndex = [int]$savedProgress.current_index }
    if ($script:readCount -lt 0 -or $script:currentIndex -lt 0 -or $script:currentIndex -gt $verses.Count) { throw 'Invalid saved reading progress.' }
}
[xml]$layout = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
 Title="آية من القرآن" Width="760" Height="500" WindowStartupLocation="CenterScreen"
 Topmost="True" ShowActivated="False" ShowInTaskbar="False" ResizeMode="NoResize"
 WindowStyle="None" AllowsTransparency="True" Background="Transparent" FlowDirection="RightToLeft">
 <Border Name="BackgroundCard" CornerRadius="22" BorderBrush="#608D99" BorderThickness="1">
  <Border Background="#AA0F2933" CornerRadius="22" Padding="32">
  <Grid>
   <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
   <TextBlock Name="Reference" Foreground="#FFF5DF" FontSize="18" TextAlignment="Center"/>
   <TextBlock Name="Progress" Grid.Row="1" Margin="0,8,0,22" Foreground="#DFEDF0" FontSize="13" TextAlignment="Center"/>
   <ScrollViewer Name="VerseScroll" Grid.Row="2" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
    <StackPanel VerticalAlignment="Center">
     <TextBlock Name="Verse" FontFamily="Traditional Arabic, Segoe UI" Foreground="#FFFFFF" TextWrapping="Wrap" TextAlignment="Center" Padding="8"/>
     <TextBlock Name="Translation" FontFamily="Segoe UI" FontSize="21" Foreground="#F1F5F5" FlowDirection="LeftToRight" TextWrapping="Wrap" TextAlignment="Center" Margin="12,12,12,16"/>
     <TextBlock Name="VerseNumber" FontFamily="Georgia" FontSize="17" Foreground="#FFF5DF" FlowDirection="LeftToRight" TextAlignment="Center" Margin="0,6,0,8"/>
     <StackPanel Name="AdditionalVerses"/>
    </StackPanel>
   </ScrollViewer>
   <WrapPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,24,0,0">
    <Button Name="Read" Content="✓  قرأتها" Background="#194957" Foreground="White" FontSize="18" Padding="24,10" Margin="6,0"/>
    <Button Name="Tafsir" Content="التفسير" Background="#DAE9EB" Foreground="#183B46" FontSize="16" Padding="18,10" Margin="6,0"/>
    <Button Name="Settings" Content="الإعدادات" Background="#DAE9EB" Foreground="#183B46" FontSize="16" Padding="18,10" Margin="6,0"/>
    <Button Name="Hide" Content="إخفاء" Background="Transparent" BorderBrush="#7AA5B2" Foreground="White" FontSize="16" Padding="18,10" Margin="6,0" ToolTip="إخفاء دون تسجيل قراءة"/>
   </WrapPanel>
  </Grid>
  </Border>
 </Border>
</Window>
'@
$window = [Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($layout))
Initialize-WindowStyle $window
$customBackgroundPath = Join-Path $store 'custom-background.png'
function Get-BackgroundImage($imagePath) {
    $imageStream = [IO.File]::OpenRead($imagePath)
    try {
        $bitmap = [Windows.Media.Imaging.BitmapImage]::new()
        $bitmap.BeginInit()
        $bitmap.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bitmap.StreamSource = $imageStream
        $bitmap.EndInit()
        $bitmap.Freeze()
        return $bitmap
    } finally { $imageStream.Dispose() }
}
function Update-Background {
    $backgroundPath = Join-Path $PSScriptRoot 'background.png'
    if (Test-Path $customBackgroundPath) { $backgroundPath = $customBackgroundPath }
    $backgroundBrush = [Windows.Media.ImageBrush]::new((Get-BackgroundImage $backgroundPath))
    $backgroundBrush.Stretch = [Windows.Media.Stretch]::UniformToFill
    $backgroundBrush.AlignmentY = [Windows.Media.AlignmentY]::Bottom
    $window.FindName('BackgroundCard').Background = $backgroundBrush
}
Update-Background
$window.Width = [Math]::Min(1040, [Windows.SystemParameters]::WorkArea.Width - 48)
$window.Height = [Math]::Min(500, [Windows.SystemParameters]::WorkArea.Height - 32)
$verseText = $window.FindName('Verse')
$translationText = $window.FindName('Translation')
$verseNumberText = $window.FindName('VerseNumber')
$verseText.FontSize = $fontSize
$reference = $window.FindName('Reference')
$progressText = $window.FindName('Progress')
$readButton = $window.FindName('Read')
$timer = [Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [TimeSpan]::FromSeconds($script:readingIntervalSeconds)
$expiry = [Windows.Threading.DispatcherTimer]::new()
$expiry.Interval = [TimeSpan]::FromSeconds([Math]::Max(1, [int]$config.auto_hide_seconds))
function Hide-Verse {
    $expiry.Stop()
    $window.Hide()
    $timer.Stop()
    $timer.Start()
}
function Add-VersePanel($verse) {
    [xml]$verseLayout = @'
<StackPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Margin="0,18,0,0">
 <Border Height="1" Background="#668BA9B2" Margin="48,0,48,18"/>
 <TextBlock FontFamily="Traditional Arabic, Segoe UI" Foreground="White" TextWrapping="Wrap" TextAlignment="Center" Padding="8"/>
 <TextBlock FontFamily="Segoe UI" FontSize="21" Foreground="#F1F5F5" FlowDirection="LeftToRight" TextWrapping="Wrap" TextAlignment="Center" Margin="12,12,12,16"/>
 <TextBlock FontFamily="Georgia" FontSize="17" Foreground="#FFF5DF" FlowDirection="LeftToRight" TextAlignment="Center" Margin="0,6,0,8"/>
</StackPanel>
'@
    $versePanel = [Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($verseLayout))
    $versePanel.Children[1].Text = $verse.arabic
    $versePanel.Children[1].FontSize = $fontSize
    $versePanel.Children[2].Text = $verse.english
    $versePanel.Children[3].Text = 'Quran ' + $verse.surah_number + ':' + $verse.ayah
    $window.FindName('AdditionalVerses').Children.Add($versePanel) | Out-Null
}
function Update-TranslationVisibility {
    $translationVisibility = [Windows.Visibility]::Collapsed
    if ($script:showTranslation) { $translationVisibility = [Windows.Visibility]::Visible }
    $translationText.Visibility = $translationVisibility
    foreach ($versePanel in $window.FindName('AdditionalVerses').Children) {
        $versePanel.Children[2].Visibility = $translationVisibility
    }
}
function Resize-Reminder {
    $availableHeight = [Windows.SystemParameters]::WorkArea.Height - 48
    $readingContent = $window.FindName('VerseScroll').Content
    $readingContent.InvalidateMeasure()
    $readingContent.Measure([Windows.Size]::new($window.Width - 82, [double]::PositiveInfinity))
    $requiredHeight = [Math]::Ceiling($readingContent.DesiredSize.Height) + 214
    $window.Height = [Math]::Min($availableHeight, [Math]::Max(540, $requiredHeight))
    $readingContent.InvalidateMeasure()
    $window.FindName('VerseScroll').InvalidateMeasure()
}
function Show-Verse {
    if ($script:memorizationSettingsOpen) { $script:readingPending = $true; return }
    $script:readingPending = $false
    $timer.Stop()
    $expiry.Stop()
    $window.FindName('AdditionalVerses').Children.Clear()
    $script:displayedCount = [Math]::Min($script:versesPerReminder, $verses.Count - $script:currentIndex)
    if ($script:currentIndex -eq $verses.Count) {
        $reference.Text = 'وصلت إلى نهاية المصحف'
        $verseText.Text = 'بارك الله فيك'
        $translationText.Text = ''
        $verseNumberText.Text = ''
        $readButton.IsEnabled = $false
    } else {
        $readButton.IsEnabled = $true
        $currentVerse = $verses[$script:currentIndex]
        $reference.Text = $currentVerse.surah_name + ' · الآية ' + $currentVerse.ayah
        $verseText.Text = $currentVerse.arabic
        $translationText.Text = $currentVerse.english
        $verseNumberText.Text = 'Quran ' + $currentVerse.surah_number + ':' + $currentVerse.ayah
        for ($offset = 1; $offset -lt $script:displayedCount; $offset++) {
            Add-VersePanel $verses[$script:currentIndex + $offset]
        }
        if ($script:displayedCount -gt 1) { $reference.Text += ' · ' + $script:displayedCount + ' آيات متتالية' }
    }
    $progressText.Text = 'الآيات التي أكدت قراءتها: ' + $script:readCount
    $readButton.Content = '✓  قرأتها'
    if ($script:displayedCount -gt 1) { $readButton.Content = '✓  قرأتها كلها' }
    $window.FindName('Tafsir').IsEnabled = $script:displayedCount -gt 0
    Update-TranslationVisibility
    Resize-Reminder
    $window.FindName('VerseScroll').ScrollToTop()
    $window.Show()
    $window.UpdateLayout()
    $window.Left = ([Windows.SystemParameters]::WorkArea.Width - $window.ActualWidth) / 2 + [Windows.SystemParameters]::WorkArea.Left
    $window.Top = ([Windows.SystemParameters]::WorkArea.Height - $window.ActualHeight) / 2 + [Windows.SystemParameters]::WorkArea.Top
    if ([int]$config.auto_hide_seconds -gt 0) { $expiry.Start() }
}
function Save-Progress($readingRecord) {
    $serialized = $readingRecord | ConvertTo-Json
    $pendingPath = $statePath + '.tmp'
    [IO.File]::WriteAllText($pendingPath, $serialized, [Text.Encoding]::UTF8)
    if (Test-Path $statePath) { [IO.File]::Replace($pendingPath, $statePath, $statePath + '.bak') }
    else { [IO.File]::Move($pendingPath, $statePath) }
}
function Confirm-Reading {
    if (-not $window.IsVisible -or $script:currentIndex -ge $verses.Count) { return }
    Save-Progress @{ read_count = ($script:readCount + $script:displayedCount); current_index = ($script:currentIndex + $script:displayedCount) }
    $script:readCount += $script:displayedCount
    $script:currentIndex += $script:displayedCount
    Hide-Verse
}
. (Join-Path $PSScriptRoot 'settings.ps1')
. (Join-Path $PSScriptRoot 'tafsir.ps1')
. (Join-Path $PSScriptRoot 'memorization.ps1')
$window.FindName('Tafsir').Add_Click({ Show-Tafsir })
$window.FindName('Settings').Add_Click({ Show-Settings })
$readButton.Add_Click({ Confirm-Reading })
$window.FindName('Hide').Add_Click({ Hide-Verse })
$timer.Add_Tick({ Show-Verse })
$expiry.Add_Tick({ Hide-Verse })
$window.Add_Closing({ param($sender, $eventArgs) $eventArgs.Cancel = $true; Hide-Verse })
if ($Check) {
    $script:versesPerReminder = 1
    $initialCount = $script:readCount
    Show-Verse
    Hide-Verse
    if ($script:readCount -ne $initialCount) { throw 'Hiding changed reading progress.' }
    Show-Verse
    Confirm-Reading
    if ($window.IsVisible) { throw 'Read confirmation did not hide the popup.' }
    if ($script:readCount -ne $initialCount + 1) { throw 'Reading progress did not advance.' }
    $savedCount = [int](Get-Content $statePath -Raw -Encoding UTF8 | ConvertFrom-Json).read_count
    if ($savedCount -ne $script:readCount) { throw 'Reading progress was not saved.' }
    Show-Verse
    if ($verseText.Text -ne $verses[$script:currentIndex].arabic) { throw 'Next verse text mismatch.' }
    if ($translationText.Text -ne $verses[$script:currentIndex].english) { throw 'Translation mismatch.' }
    $expectedReference = 'Quran ' + $verses[$script:currentIndex].surah_number + ':' + $verses[$script:currentIndex].ayah
    if ($verseNumberText.Text -ne $expectedReference) { throw 'Verse reference mismatch.' }
    $countBeforeJump = $script:readCount
    Set-StartingVerse 2993
    Show-Verse
    if ($verseNumberText.Text -ne 'Quran 26:62' -or $script:readCount -ne $countBeforeJump) { throw 'Starting verse changed reading count or used the wrong reference.' }
    $jumpRecord = Get-Content $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($jumpRecord.current_index -ne 2993) { throw 'Starting verse was not saved.' }
    $settingsCheck = New-SettingsWindow
    $settingsCheck.FindName('Surah').Items.Add([pscustomobject]@{ Label = '26'; Number = 26 }) | Out-Null
    $settingsCheck.FindName('Surah').SelectedIndex = 0
    Update-AyahChoices $settingsCheck
    if ($settingsCheck.FindName('Ayah').Items.Count -ne 227) { throw 'Surah ayah choices mismatch.' }
    $settingsCheck.FindName('Surah').Items.Clear()
    foreach ($verse in $verses) { if ($verse.ayah -eq 1) { $settingsCheck.FindName('Surah').Items.Add([pscustomobject]@{Label=$verse.surah_name;Number=$verse.surah_number}) | Out-Null } }
    $settingsCheck.FindName('Surah').Text = 'الفاتحة'
    Search-Surahs $settingsCheck
    if ($settingsCheck.FindName('Surah').Items.Count -ne 1 -or $settingsCheck.FindName('Surah').Items[0].Number -ne 1) { throw 'Unvocalized surah search failed.' }
    $settingsCheck.FindName('Surah').Text = 'مريم'
    Search-Surahs $settingsCheck
    if ($settingsCheck.FindName('Surah').Items.Count -ne 1 -or $settingsCheck.FindName('Surah').Items[0].Number -ne 19) { throw 'Surah name search mismatch.' }
    $settingsCheck.FindName('Surah').Text = 'غيرموجود'
    Search-Surahs $settingsCheck
    Update-AyahChoices $settingsCheck
    if ($settingsCheck.FindName('Surah').Items.Count -ne 0 -or $settingsCheck.FindName('Ayah').Items.Count -ne 0) { throw 'Empty search kept stale choices.' }
    $settingsCheck.FindName('Surah').Text = ''
    Search-Surahs $settingsCheck
    if ($settingsCheck.FindName('Surah').Items.Count -ne 114) { throw 'Clearing search did not restore all surahs.' }
    Set-CustomBackground (Join-Path $PSScriptRoot 'background.png')
    if (-not (Test-Path $customBackgroundPath)) { throw 'Custom background was not saved.' }
    Update-Background
    if ($script:readingIntervalSeconds -ne 300) { throw 'Default reading interval must be five minutes.' }
    Save-DisplayPreferences @{ verses_per_reminder = 1; show_translation = $true; reading_interval_seconds = 420 }
    if ($timer.Interval.TotalSeconds -ne 420) { throw 'Reading timer was not updated.' }
    Set-VersesPerReminder 3
    $intervalRecord = Get-Content $preferencesPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($intervalRecord.reading_interval_seconds -ne 420) { throw 'Reading interval was not preserved.' }
    Set-StartingVerse 0
    Show-Verse
    Save-DisplayPreferences @{ verses_per_reminder = 3; show_translation = $false }
    Update-TranslationVisibility
    if ($translationText.Visibility -ne 'Collapsed' -or $window.FindName('AdditionalVerses').Children[0].Children[2].Visibility -ne 'Collapsed') { throw 'Translation was not hidden for the whole group.' }
    $tafsirCheck = New-TafsirWindow
    $tafsirPanels = $tafsirCheck.FindName('TafsirContent').Children
    if ($tafsirPanels.Count -ne 3 -or $tafsirPanels[2].Children[1].Text -ne $verses[2].tafsir) { throw 'Tafsir group mismatch.' }
    $translationRecord = Get-Content $preferencesPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($translationRecord.show_translation -ne $false) { throw 'Translation preference was not saved.' }
    Save-DisplayPreferences @{ verses_per_reminder = 3; show_translation = $true }
    Update-TranslationVisibility
    if ($translationText.Visibility -ne 'Visible') { throw 'Translation was not restored.' }
    Show-Verse
    if ($script:displayedCount -ne 3 -or $window.FindName('AdditionalVerses').Children.Count -ne 2) { throw 'Multiple verse display mismatch.' }
    $thirdPanel = $window.FindName('AdditionalVerses').Children[1]
    if ($thirdPanel.Children[2].Text -ne $verses[2].english -or $thirdPanel.Children[3].Text -ne 'Quran 1:3') { throw 'Grouped translation or reference mismatch.' }
    $countBeforeBatch = $script:readCount
    Hide-Verse
    Show-Verse
    if ($script:currentIndex -ne 0) { throw 'Hiding skipped verses.' }
    Confirm-Reading
    if ($script:currentIndex -ne 3 -or $script:readCount -ne $countBeforeBatch + 3) { throw 'Batch confirmation did not advance by three verses.' }
    Set-StartingVerse 5
    Show-Verse
    $boundaryPanel = $window.FindName('AdditionalVerses').Children[1]
    if ($boundaryPanel.Children[3].Text -ne 'Quran 2:1') { throw 'Batch crossing a surah boundary has the wrong reference.' }
    Set-StartingVerse 6234
    Show-Verse
    if ($script:displayedCount -ne 2) { throw 'Final Quran batch exceeded remaining verses.' }
    Confirm-Reading
    Show-Verse
    if ($script:currentIndex -ne 6236 -or $readButton.IsEnabled) { throw 'Final Quran batch did not finish correctly.' }
    $savedPreferences = Get-Content $preferencesPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($savedPreferences.verses_per_reminder -ne 3) { throw 'Batch size was not saved.' }
    Set-StartingVerse 0
    Hide-Verse
    $timer.Stop()
    $readingCountBeforeMemo = $script:readCount
    $testPlan = [pscustomobject]@{enabled=$true;page=3;lines_per_part=4;repeat_count=2;interval_seconds=17;part_index=0;confirmed_repeats=0;next_due_unix=0}
    Save-Memorization $testPlan
    $memoParts = @(Get-MemorizationParts $script:memorization)
    if ($memoParts.Count -ne 4 -or $memoParts[3].lines.Count -ne 3) { throw 'Page was not divided into 4+4+4+3 actual lines.' }
    Show-Verse
    $scheduledPlan = Get-MemorizationCopy
    $scheduledPlan.next_due_unix = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 60
    Save-Memorization $scheduledPlan
    Show-DueMemorization
    if ($script:memorizationWindow -and $script:memorizationWindow.IsVisible) { throw 'Memorization appeared before its scheduled time.' }
    $scheduledPlan.next_due_unix = 0
    Save-Memorization $scheduledPlan
    $script:memorizationSettingsOpen = $true
    Show-DueMemorization
    if ($script:memorizationWindow -and $script:memorizationWindow.IsVisible) { throw 'Memorization interrupted settings.' }
    $script:memorizationSettingsOpen = $false
    Start-MemorizationTimer
    $scheduleFrame = [Windows.Threading.DispatcherFrame]::new()
    $scheduleTimeout = [Windows.Threading.DispatcherTimer]::new()
    $scheduleTimeout.Interval = [TimeSpan]::FromMilliseconds(1500)
    $scheduleTimeout.Add_Tick({ $scheduleTimeout.Stop(); $scheduleFrame.Continue = $false })
    $scheduleTimeout.Start()
    [Windows.Threading.Dispatcher]::PushFrame($scheduleFrame)
    $script:memorizationTimer.Stop()
    if (-not $script:memorizationWindow.IsVisible -or -not $window.IsVisible) { throw 'Due memorization was blocked by reading.' }
    Hide-Verse
    Show-Verse
    if (-not $window.IsVisible -or -not $script:memorizationWindow.IsVisible) { throw 'Reading was blocked by memorization.' }
    Hide-Memorization
    Hide-Verse
    $timer.Stop()
    if ($script:memorization.confirmed_repeats -ne 0) { throw 'Hiding a memorization part counted a review.' }
    Show-Memorization
    Confirm-Memorization
    if ($script:memorization.part_index -ne 0 -or $script:memorization.confirmed_repeats -ne 1) { throw 'Memorization advanced before the repetition target.' }
    Show-Memorization
    Confirm-Memorization
    if ($script:memorization.part_index -ne 1 -or $script:memorization.confirmed_repeats -ne 0 -or $script:readCount -ne $readingCountBeforeMemo) { throw 'Memorization progress mixed with ordinary reading.' }
    $finalMemo = Get-MemorizationCopy
    $finalMemo.part_index = 3; $finalMemo.confirmed_repeats = 1
    Save-Memorization $finalMemo
    Show-Memorization
    Confirm-Memorization
    if ($script:memorization.enabled -or $script:memorization.part_index -ne 4) { throw 'Completed page did not stop the memorization plan.' }
    $memoSettingsCheck = New-MemorizationSettingsWindow
    $memoSettingsCheck.FindName('Surah').Items.Add([pscustomobject]@{Label='مريم';Number=19}) | Out-Null
    $memoSettingsCheck.FindName('Surah').SelectedIndex = 0
    Update-MemorizationPages $memoSettingsCheck
    if ($memoSettingsCheck.FindName('Page').Items.Count -lt 1) { throw 'Surah page choices were not populated.' }
    $savedMemo = Get-Content $memorizationPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($savedMemo.interval_seconds -ne 17 -or $savedMemo.part_index -ne 4) { throw 'Custom timing or memorization position did not persist.' }
    $timer.Stop()
    'WPF loaded; 6236 verses loaded; show, confirm, save and hide passed.'
    exit
}
$created = $false
$mutex = [Threading.Mutex]::new($true, 'Local\QuranReminderWindows', [ref]$created)
if (-not $created) { $mutex.Dispose(); exit }
$tray = [Windows.Forms.NotifyIcon]::new()
$tray.Icon = [Drawing.SystemIcons]::Information
$tray.Text = 'Quran Reminder'
$menu = [Windows.Forms.ContextMenuStrip]::new()
$showMenu = $menu.Items.Add('عرض الآية')
$settingsMenu = $menu.Items.Add('الإعدادات')
$memorizationMenu = $menu.Items.Add('خطة الحفظ والمراجعة')
$exitMenu = $menu.Items.Add('إغلاق البرنامج')
$tray.ContextMenuStrip = $menu
$tray.Visible = $true
$dispatcher = [Windows.Threading.Dispatcher]::CurrentDispatcher
$showMenu.Add_Click({ Show-Verse })
$settingsMenu.Add_Click({ Show-Settings })
$memorizationMenu.Add_Click({ Show-MemorizationSettings })
$tray.Add_DoubleClick({ Show-Verse })
$exitMenu.Add_Click({ $dispatcher.InvokeShutdown() })
try { Start-MemorizationTimer; Show-Verse; [Windows.Threading.Dispatcher]::Run() }
catch {
    $_ | Out-String | Set-Content (Join-Path $store 'error.log') -Encoding UTF8
    [Windows.MessageBox]::Show($_.Exception.Message, 'Quran Reminder') | Out-Null
}
finally { $timer.Stop(); $expiry.Stop(); $tray.Dispose(); $mutex.ReleaseMutex(); $mutex.Dispose() }
