$script:mushafPages = (Get-Content (Join-Path $PSScriptRoot 'mushaf-lines.json') -Raw -Encoding UTF8 | ConvertFrom-Json).pages
if ($script:mushafPages.Count -ne 604) { throw 'Incomplete Mushaf page layout.' }
$memorizationPath = Join-Path $store 'memorization.json'
$script:memorization = [pscustomobject]@{ enabled = $false; page = 1; lines_per_part = 5; repeat_count = 3; interval_seconds = 300; part_index = 0; confirmed_repeats = 0; next_due_unix = 0 }
if (Test-Path $memorizationPath) { $script:memorization = Get-Content $memorizationPath -Raw -Encoding UTF8 | ConvertFrom-Json }
$script:memorizationWindow = $null
$script:memorizationSettingsOpen = $false
function Get-MemorizationParts($plan) {
    if ($plan.page -lt 1 -or $plan.page -gt 604 -or $plan.lines_per_part -lt 1 -or $plan.lines_per_part -gt 15) { throw 'اختَر صفحة من ١ إلى ٦٠٤، ومن ١ إلى ١٥ سطرًا.' }
    $pageLines = @($script:mushafPages[[int]$plan.page - 1].lines)
    $parts = [Collections.Generic.List[object]]::new()
    for ($start = 0; $start -lt $pageLines.Count; $start += [int]$plan.lines_per_part) {
        $end = [Math]::Min($pageLines.Count - 1, $start + [int]$plan.lines_per_part - 1)
        $parts.Add([pscustomobject]@{ lines = @($pageLines[$start..$end]) })
    }
    return $parts.ToArray()
}
function Assert-MemorizationPlan($plan) {
    if ($plan.page -lt 1 -or $plan.page -gt 604 -or $plan.lines_per_part -lt 1 -or $plan.lines_per_part -gt 15 -or $plan.repeat_count -lt 1 -or $plan.repeat_count -gt 1000 -or $plan.interval_seconds -lt 1 -or $plan.interval_seconds -gt 86400) { throw 'راجع رقم الصفحة والأسطر والتكرارات والوقت.' }
    $parts = @(Get-MemorizationParts $plan)
    if ($plan.part_index -lt 0 -or $plan.part_index -gt $parts.Count -or $plan.confirmed_repeats -lt 0 -or $plan.confirmed_repeats -ge $plan.repeat_count) { throw 'Invalid memorization progress.' }
    if ($plan.enabled -isnot [bool] -or $plan.next_due_unix -lt 0 -or ($plan.enabled -and $plan.part_index -eq $parts.Count)) { throw 'Invalid memorization schedule.' }
}
function Save-Memorization($plan) {
    Assert-MemorizationPlan $plan
    $pending = $memorizationPath + '.tmp'
    [IO.File]::WriteAllText($pending, ($plan | ConvertTo-Json), [Text.Encoding]::UTF8)
    if (Test-Path $memorizationPath) { [IO.File]::Replace($pending, $memorizationPath, $memorizationPath + '.bak') }
    else { [IO.File]::Move($pending, $memorizationPath) }
    $script:memorization = $plan
    Update-MemorizationTimer
}
function Get-MemorizationCopy { return ($script:memorization | ConvertTo-Json | ConvertFrom-Json) }
function Hide-Memorization {
    $nextPlan = Get-MemorizationCopy
    $nextPlan.next_due_unix = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + $nextPlan.interval_seconds
    Save-Memorization $nextPlan
    if ($script:memorizationWindow) { $script:memorizationWindow.Hide() }
    Update-MemorizationTimer
    if ($script:readingPending) { Show-Verse }
}
function Confirm-Memorization {
    if (-not $script:memorizationWindow.IsVisible) { return }
    $nextPlan = Get-MemorizationCopy
    $nextPlan.confirmed_repeats++
    if ($nextPlan.confirmed_repeats -ge $nextPlan.repeat_count) { $nextPlan.part_index++; $nextPlan.confirmed_repeats = 0 }
    if ($nextPlan.part_index -ge @(Get-MemorizationParts $nextPlan).Count) { $nextPlan.enabled = $false }
    $nextPlan.next_due_unix = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + $nextPlan.interval_seconds
    Save-Memorization $nextPlan
    $script:memorizationWindow.Hide()
    Update-MemorizationTimer
    if ($script:readingPending) { Show-Verse }
}
function New-MemorizationWindow {
    [xml]$markup = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="الحفظ والمراجعة" Width="1000" Height="650" Topmost="True" ShowActivated="False" ShowInTaskbar="False" WindowStartupLocation="CenterScreen" FlowDirection="RightToLeft" Background="#F7F3EA" Foreground="#183544">
 <Border Name="MemoBackground" CornerRadius="16" BorderBrush="#D8CEBA" BorderThickness="1"><Border Name="MemoVeil" CornerRadius="16" Padding="28">
 <Grid>
  <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
  <TextBlock Name="Title" FontSize="23" FontWeight="SemiBold" TextAlignment="Center"/>
  <TextBlock Name="Status" Grid.Row="1" FontSize="14" Foreground="#38515B" Margin="0,12,0,20" TextAlignment="Center"/>
  <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto"><StackPanel Name="Lines"/></ScrollViewer>
  <WrapPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,20,0,0">
   <Button Name="Confirm" Content="✓ تمت المراجعة" Background="#24596A" Foreground="White" Margin="6,0"/>
   <Button Name="Hide" Content="إخفاء دون تسجيل" Margin="6,0"/>
  </WrapPanel>
 </Grid>
 </Border></Border>
</Window>
'@
    $memoWindow = [Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($markup))
    Initialize-WindowStyle $memoWindow
    Apply-ReminderBackground $memoWindow 'MemoBackground' 'MemoVeil'
    $memoWindow.Width = [Math]::Min(1000, [Windows.SystemParameters]::WorkArea.Width - 48)
    $memoWindow.Height = [Math]::Min(650, [Windows.SystemParameters]::WorkArea.Height - 48)
    $memoWindow.FindName('Confirm').Add_Click({ Confirm-Memorization })
    $memoWindow.FindName('Hide').Add_Click({ Hide-Memorization })
    $memoWindow.Add_Closing({ param($sender, $eventArgs) $eventArgs.Cancel = $true; Hide-Memorization })
    return $memoWindow
}
function Show-Memorization {
    $parts = @(Get-MemorizationParts $script:memorization)
    if ($script:memorization.part_index -ge $parts.Count) { return }
    if (-not $script:memorizationWindow) { $script:memorizationWindow = New-MemorizationWindow }
    $part = $parts[$script:memorization.part_index]
    $script:memorizationWindow.FindName('Title').Text = 'حفظ صفحة ' + $script:memorization.page + ' · الجزء ' + ($script:memorization.part_index + 1) + ' من ' + $parts.Count
    $script:memorizationWindow.FindName('Status').Text = 'المراجعة ' + ($script:memorization.confirmed_repeats + 1) + ' من ' + $script:memorization.repeat_count + ' · أسطر المصحف ' + $part.lines[0].number + '–' + $part.lines[-1].number + ' · قد يبدأ المقطع أو ينتهي داخل آية'
    $linePanel = $script:memorizationWindow.FindName('Lines')
    $linePanel.Children.Clear()
    foreach ($line in $part.lines) {
        $label = [Windows.Controls.TextBlock]::new()
        $label.Text = $line.text
        $label.FontFamily = [Windows.Media.FontFamily]::new('Traditional Arabic')
        $label.FontSize = $fontSize
        $label.TextAlignment = [Windows.TextAlignment]::Center
        $label.TextWrapping = [Windows.TextWrapping]::Wrap
        $label.Margin = [Windows.Thickness]::new(0, 8, 0, 8)
        $linePanel.Children.Add($label) | Out-Null
    }
    $script:memorizationWindow.Show()
}
function Update-MemorizationPages($planWindow) {
    $chapter = $planWindow.FindName('Surah').SelectedItem.Number
    $pageChoices = $planWindow.FindName('Page')
    $pageChoices.Items.Clear()
    if ($null -eq $chapter) { return }
    foreach ($page in $script:mushafPages) {
        $matches = @($page.lines.references | Where-Object { $_ -like ($chapter.ToString() + ':*') })
        if ($matches.Count -gt 0) { $pageChoices.Items.Add([pscustomobject]@{Label=('الصفحة ' + $page.number); Number=$page.number}) | Out-Null }
    }
    $pageChoices.SelectedIndex = 0
}
function New-MemorizationSettingsWindow {
    [xml]$markup = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="خطة الحفظ والمراجعة" Width="600" Height="680" WindowStartupLocation="CenterScreen" Topmost="True" FlowDirection="RightToLeft" Background="#F4F8F9" Foreground="#193E49" FontSize="16">
 <Grid Margin="28"><Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
  <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel>
   <TextBlock Text="خطة حفظ مستقلة" FontSize="25" FontWeight="SemiBold" Margin="0,0,0,14"/>
   <TextBlock Text="توقيت منفصل عن القراءة. التكرار يُسجل عند ضغط تمت المراجعة." TextWrapping="Wrap" Foreground="#607D86" Margin="0,0,0,18"/>
   <TextBlock Text="السورة"/><ComboBox Name="Surah" DisplayMemberPath="Label" MinHeight="36" Margin="0,6,0,12"/>
   <TextBlock Text="الصفحة في مصحف المدينة — ٦٠٤ صفحات"/><ComboBox Name="Page" DisplayMemberPath="Label" MinHeight="36" Margin="0,6,0,12"/>
   <TextBlock Text="عدد الأسطر في كل جزء (١–١٥)"/><TextBox Name="LinesPerPart" Padding="10" Margin="0,6,0,12"/>
   <TextBlock Text="مرات مراجعة كل جزء قبل الانتقال للتالي"/><TextBox Name="Repeats" Padding="10" Margin="0,6,0,12"/>
   <TextBlock Text="الفاصل الزمني الذي تختاره"/>
   <StackPanel Orientation="Horizontal" Margin="0,6,0,16"><TextBox Name="Interval" Width="180" Padding="10"/><ComboBox Name="Unit" Width="160" SelectedIndex="1" Margin="12,0"><ComboBoxItem Content="ثوانٍ"/><ComboBoxItem Content="دقائق"/><ComboBoxItem Content="ساعات"/></ComboBox></StackPanel>
   <CheckBox Name="Restart" Content="ابدأ الخطة من أول الصفحة" Margin="0,0,0,12"/>
   <CheckBox Name="Enabled" Content="تفعيل التذكير بالحفظ" Margin="0,0,0,12"/>
   <TextBlock Name="Progress" TextWrapping="Wrap" Foreground="#607D86"/>
  </StackPanel></ScrollViewer>
  <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,20,0,0" HorizontalAlignment="Center"><Button Name="Save" Content="حفظ الخطة" Background="#24596A" Foreground="White" Margin="6,0"/><Button Name="Cancel" Content="إلغاء" IsCancel="True" Margin="6,0"/></StackPanel>
 </Grid>
</Window>
'@
    $planWindow = [Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($markup))
    Initialize-WindowStyle $planWindow
    $planWindow.Height = [Math]::Min(680, [Windows.SystemParameters]::WorkArea.Height - 48)
    return $planWindow
}
function Show-MemorizationSettings {
    Show-Settings 1
}
function Initialize-MemorizationTab($hostWindow) {
    $script:memorizationSettingsOpen = $true
    try {
        $planWindow = New-MemorizationSettingsWindow
        $planWindow.Tag = $hostWindow
        $unitChoices = $planWindow.FindName('Unit')
        $unitChoices.Items.Clear()
        $unitChoices.DisplayMemberPath = 'Label'
        foreach ($unitLabel in @('ثوانٍ','دقائق','ساعات')) { $unitChoices.Items.Add([pscustomobject]@{Label=$unitLabel}) | Out-Null }
        foreach ($verse in $verses) { if ($verse.ayah -eq 1) { $planWindow.FindName('Surah').Items.Add([pscustomobject]@{Label=$verse.surah_name;Number=$verse.surah_number}) | Out-Null } }
        $planWindow.FindName('Surah').Add_SelectionChanged({ Update-MemorizationPages $planWindow })
        Enable-SurahSearch $planWindow
        $firstReference = $script:mushafPages[$script:memorization.page - 1].lines[0].references[0]
        $planWindow.FindName('Surah').SelectedIndex = [int]$firstReference.Split(':')[0] - 1
        foreach ($choice in $planWindow.FindName('Page').Items) { if ($choice.Number -eq $script:memorization.page) { $planWindow.FindName('Page').SelectedItem = $choice; break } }
        $planWindow.FindName('LinesPerPart').Text = $script:memorization.lines_per_part
        $planWindow.FindName('Repeats').Text = $script:memorization.repeat_count
        $planWindow.FindName('Interval').Text = $script:memorization.interval_seconds
        $planWindow.FindName('Unit').SelectedIndex = 0
        $planWindow.FindName('Enabled').IsChecked = $true
        $planWindow.FindName('Save').Content = 'حفظ وتشغيل الخطة'
        $planWindow.FindName('Enabled').Add_Click({
            if ($planWindow.FindName('Enabled').IsChecked) { $planWindow.FindName('Save').Content = 'حفظ وتشغيل الخطة' }
            else { $planWindow.FindName('Save').Content = 'حفظ الخطة بدون تشغيل' }
        })
        $planWindow.FindName('Progress').Text = 'الموضع الحالي: الجزء ' + ($script:memorization.part_index + 1) + ' · المراجعات المكتملة فيه: ' + $script:memorization.confirmed_repeats
        $planWindow.FindName('Cancel').Visibility = [Windows.Visibility]::Collapsed
        $planWindow.FindName('Save').Add_Click({
            try {
                $nextPlan = Get-MemorizationCopy
                $page = [int]$planWindow.FindName('Page').SelectedItem.Number
                $lineCount = [int]$planWindow.FindName('LinesPerPart').Text
                $repeats = [int]$planWindow.FindName('Repeats').Text
                if ($planWindow.FindName('Restart').IsChecked -or $page -ne $nextPlan.page -or $lineCount -ne $nextPlan.lines_per_part -or $repeats -ne $nextPlan.repeat_count) { $nextPlan.part_index = 0; $nextPlan.confirmed_repeats = 0 }
                $nextPlan.page = $page; $nextPlan.lines_per_part = $lineCount; $nextPlan.repeat_count = $repeats
                $nextPlan.interval_seconds = [int]([double]$planWindow.FindName('Interval').Text * @(1,60,3600)[$planWindow.FindName('Unit').SelectedIndex])
                $nextPlan.enabled = [bool]$planWindow.FindName('Enabled').IsChecked
                if ($nextPlan.enabled -and $nextPlan.part_index -ge @(Get-MemorizationParts $nextPlan).Count) { throw 'الخطة مكتملة. فعّل ابدأ الخطة من أول الصفحة لإعادتها.' }
                $nextPlan.next_due_unix = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + $nextPlan.interval_seconds
                Save-Memorization $nextPlan
                $planWindow.Tag.Tag = 'memorization-saved'
                $planWindow.Tag.Close()
            } catch { [Windows.MessageBox]::Show($planWindow, $_.Exception.Message, 'راجع إعدادات الحفظ') | Out-Null }
        })
        $panel = $planWindow.Content
        $panel.Margin = [Windows.Thickness]::new(8)
        [Windows.Documents.TextElement]::SetForeground($panel, [Windows.Media.BrushConverter]::new().ConvertFromString('#193E49'))
        $planWindow.Content = $null
        $hostWindow.FindName('MemorizationTab').Content = $panel
        return $planWindow
    } finally { $script:memorizationSettingsOpen = $false; if ($script:readingPending) { Show-Verse } }
}
function Show-DueMemorization {
    if (-not $script:memorization.enabled -or $script:memorizationSettingsOpen) { return }
    if ($script:memorizationWindow -and $script:memorizationWindow.IsVisible) { return }
    if ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() -lt $script:memorization.next_due_unix) { return }
    Show-Memorization
}
function Update-MemorizationTimer {
    if (-not $script:memorizationTimer) { return }
    $script:memorizationTimer.Stop()
    if (-not $script:memorization.enabled) { return }
    $remaining = $script:memorization.next_due_unix - [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if (($script:memorizationWindow -and $script:memorizationWindow.IsVisible) -or $script:memorizationSettingsOpen) { $remaining = 30 }
    $script:memorizationTimer.Interval = [TimeSpan]::FromSeconds([Math]::Max(1, [Math]::Min(30, $remaining)))
    $script:memorizationTimer.Start()
}
function Start-MemorizationTimer {
    $script:memorizationTimer = [Windows.Threading.DispatcherTimer]::new()
    $script:memorizationTimer.Interval = [TimeSpan]::FromSeconds(1)
    $script:memorizationTimer.Add_Tick({ Show-DueMemorization; Update-MemorizationTimer })
    Update-MemorizationTimer
}
Assert-MemorizationPlan $script:memorization
