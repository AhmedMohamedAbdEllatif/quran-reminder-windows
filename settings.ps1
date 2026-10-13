function Set-StartingVerse($verseIndex) {
    if ($verseIndex -lt 0 -or $verseIndex -ge $verses.Count) { throw 'Invalid starting verse.' }
    Save-Progress @{ read_count = $script:readCount; current_index = $verseIndex }
    $script:currentIndex = $verseIndex
}
function Set-VersesPerReminder($verseCount) {
    if ($verseCount -lt 1 -or $verseCount -gt 20) { throw 'Choose between 1 and 20 verses.' }
    Save-DisplayPreferences @{ verses_per_reminder = $verseCount; show_translation = $script:showTranslation }
}
function Save-DisplayPreferences($readingPreferences) {
    if ($readingPreferences.verses_per_reminder -lt 1 -or $readingPreferences.verses_per_reminder -gt 20) { throw 'Choose between 1 and 20 verses.' }
    if ($readingPreferences.show_translation -isnot [bool]) { throw 'Invalid translation preference.' }
    $serializedPreferences = $readingPreferences | ConvertTo-Json
    $pendingPreferencesPath = $preferencesPath + '.tmp'
    [IO.File]::WriteAllText($pendingPreferencesPath, $serializedPreferences, [Text.Encoding]::UTF8)
    if (Test-Path $preferencesPath) { [IO.File]::Replace($pendingPreferencesPath, $preferencesPath, $preferencesPath + '.bak') }
    else { [IO.File]::Move($pendingPreferencesPath, $preferencesPath) }
    $script:versesPerReminder = $readingPreferences.verses_per_reminder
    $script:showTranslation = $readingPreferences.show_translation
}
function Set-CustomBackground($imagePath) {
    $validatedImage = Get-BackgroundImage $imagePath
    $encoder = [Windows.Media.Imaging.PngBitmapEncoder]::new()
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($validatedImage))
    $pendingImagePath = $customBackgroundPath + '.tmp'
    $imageOutput = [IO.File]::Create($pendingImagePath)
    try { $encoder.Save($imageOutput) } finally { $imageOutput.Dispose() }
    if (Test-Path $customBackgroundPath) { [IO.File]::Replace($pendingImagePath, $customBackgroundPath, $customBackgroundPath + '.bak') }
    else { [IO.File]::Move($pendingImagePath, $customBackgroundPath) }
    Update-Background
}
function New-SettingsWindow {
    [xml]$settingsLayout = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="إعدادات تذكير القرآن"
 Width="680" Height="790" WindowStartupLocation="CenterScreen" ResizeMode="CanResize"
 MinWidth="440" MinHeight="420" Topmost="True" Background="#F4F8F9" Foreground="#193E49"
 FlowDirection="RightToLeft" FontFamily="Segoe UI" FontSize="16">
 <Window.Resources>

  <Style TargetType="ComboBox">
   <Setter Property="MinHeight" Value="46"/><Setter Property="FontSize" Value="16"/>
   <Setter Property="ScrollViewer.CanContentScroll" Value="True"/>
   <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ComboBox">
    <Grid FlowDirection="LeftToRight">
     <ToggleButton Focusable="False" IsChecked="{Binding IsDropDownOpen, RelativeSource={RelativeSource TemplatedParent}, Mode=TwoWay}">
      <ToggleButton.Template><ControlTemplate TargetType="ToggleButton">
       <Border Name="ChoiceSurface" Background="White" BorderBrush="#C7DBE1" BorderThickness="1" CornerRadius="9">
        <TextBlock Text="⌄" HorizontalAlignment="Left" VerticalAlignment="Center" Margin="15,0" Foreground="#397184" FontSize="20"/>
       </Border>
       <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="ChoiceSurface" Property="BorderBrush" Value="#31849A"/></Trigger></ControlTemplate.Triggers>
      </ControlTemplate></ToggleButton.Template>
     </ToggleButton>
     <TextBlock Margin="42,8,14,8" FlowDirection="RightToLeft" VerticalAlignment="Center" IsHitTestVisible="False" TextTrimming="CharacterEllipsis"
      Text="{Binding SelectedItem.Label, RelativeSource={RelativeSource TemplatedParent}}"/>
     <Popup Name="PART_Popup" IsOpen="{TemplateBinding IsDropDownOpen}" Placement="Bottom" AllowsTransparency="True" Focusable="False">
      <Border Background="White" FlowDirection="RightToLeft" BorderBrush="#C7DBE1" BorderThickness="1" CornerRadius="8" Padding="4"
       MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}">
       <ScrollViewer MaxHeight="260"><ItemsPresenter KeyboardNavigation.DirectionalNavigation="Contained"/></ScrollViewer>
      </Border>
     </Popup>
    </Grid>
    <ControlTemplate.Triggers>
     <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger>
     <Trigger Property="IsKeyboardFocusWithin" Value="True"><Setter Property="Foreground" Value="#14738B"/></Trigger>
    </ControlTemplate.Triggers>
   </ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style TargetType="ComboBoxItem"><Setter Property="Padding" Value="12,8"/></Style>
 </Window.Resources>
 <Grid Margin="28,22">
  <Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
  <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
   <StackPanel Margin="0,0,0,16">
    <TextBlock Text="على طريقتك" FontSize="27" FontWeight="SemiBold"/>
    <Button Name="Memorization" Content="خطة الحفظ والمراجعة" Margin="0,12,0,0"/>
    <TextBlock Text="اختَر خلفية تحبها، وابدأ من الآية اللي تناسبك." Foreground="#607D86" FontSize="14" Margin="0,5,0,22" TextWrapping="Wrap"/>
    <TextBlock Text="خلفية الآيات" FontWeight="SemiBold" Margin="0,0,0,10"/>
    <Border Name="ImagePreview" Height="100" CornerRadius="12" Margin="0,0,0,12">
     <Border Background="#660F2933" CornerRadius="12"><TextBlock Text="معاينة الخلفية" Foreground="White" FontSize="18" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
    </Border>
    <Button Name="ChooseImage" Content="اختيار صورة من الجهاز" HorizontalAlignment="Right"/>
    <TextBlock Name="ImageName" Text="الخلفية الحالية" Foreground="#607D86" FontSize="13" TextWrapping="Wrap" Margin="0,8,0,22"/>
    <Border Height="1" Background="#DCE8EC" Margin="0,0,0,20"/>
    <TextBlock Text="عدد الآيات في كل تذكير" FontWeight="SemiBold" Margin="0,0,0,10"/>
    <ComboBox Name="VerseCount" DisplayMemberPath="Label"/>
    <CheckBox Name="ShowTranslation" Content="إظهار الترجمة الإنجليزية" Margin="0,14,0,0" VerticalContentAlignment="Center"/>
    <TextBlock Text="آيات متتالية، مع ترجمة ورقم كل آية. زر القراءة يؤكد المجموعة كلها." Foreground="#607D86" FontSize="13" TextWrapping="Wrap" Margin="0,8,0,20"/>
    <TextBlock Text="بداية القراءة" FontWeight="SemiBold" Margin="0,0,0,10"/>
    <CheckBox Name="ChangeStart" Content="اختيار سورة وآية جديدة" Margin="0,0,0,16" VerticalContentAlignment="Center"/>
    <TextBlock Text="ابحث باسم السورة أو رقمها" FontSize="13" Foreground="#607D86" Margin="0,0,0,6"/>
    <Border Background="White" BorderBrush="#C7DBE1" BorderThickness="1" CornerRadius="9" Padding="12,9" Margin="0,0,0,6">
     <TextBox Name="SurahSearch" IsEnabled="False" Background="Transparent" BorderThickness="0" FontSize="16"/>
    </Border>
    <TextBlock Name="SearchStatus" FontSize="12" Foreground="#607D86" Margin="0,0,0,10"/>
    <Grid>
     <Grid.ColumnDefinitions><ColumnDefinition Width="2*"/><ColumnDefinition Width="14"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
     <StackPanel><TextBlock Text="السورة" FontSize="13" Foreground="#607D86" Margin="0,0,0,6"/>
      <ComboBox Name="Surah" DisplayMemberPath="Label" IsEnabled="False"/></StackPanel>
     <StackPanel Grid.Column="2"><TextBlock Text="الآية" FontSize="13" Foreground="#607D86" Margin="0,0,0,6"/>
      <ComboBox Name="Ayah" DisplayMemberPath="Label" IsEnabled="False"/></StackPanel>
    </Grid>
    <TextBlock Text="تقدمك محفوظ. تغيير البداية لا يحسب الآيات السابقة كمقروءة." Foreground="#607D86" FontSize="13" TextWrapping="Wrap" Margin="0,12,0,0"/>
   </StackPanel>
  </ScrollViewer>
  <Grid Grid.Row="1" Margin="0,14,0,0">
   <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
   <Button Name="Apply" Content="حفظ وعرض الآية" Background="#24596A" Foreground="White" BorderBrush="#24596A" FontWeight="SemiBold" IsDefault="True" Margin="0,0,12,0"/>
   <Button Name="Cancel" Grid.Column="1" Content="إلغاء" IsCancel="True"/>
  </Grid>
 </Grid>
</Window>
'@
    $settingsWindow = [Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($settingsLayout))
    Initialize-WindowStyle $settingsWindow
    $settingsWindow.Height = [Math]::Min(790, [Windows.SystemParameters]::WorkArea.Height - 32)
    return $settingsWindow
}
function Update-AyahChoices($settingsWindow) {
    $surahChoice = $settingsWindow.FindName('Surah').SelectedItem
    $ayahChoices = $settingsWindow.FindName('Ayah')
    $ayahChoices.Items.Clear()
    if ($null -eq $surahChoice) { return }
    foreach ($verse in $verses) {
        if ($verse.surah_number -eq $surahChoice.Number) {
            $ayahChoices.Items.Add([pscustomobject]@{ Label = ('الآية ' + $verse.ayah); Index = ([int]$verse.number - 1) }) | Out-Null
        }
    }
    $ayahChoices.SelectedIndex = 0
}
function Get-SurahSearchText($searchText) {
    $normalizedText = [regex]::Replace($searchText.Normalize([Text.NormalizationForm]::FormD), '\p{M}|[\u06D6-\u06ED]|\u0640', '')
    return $normalizedText.Replace('ٱ', 'ا').Replace('ى', 'ي').Trim()
}
function Search-Surahs($settingsWindow) {
    $surahChoices = $settingsWindow.FindName('Surah')
    $previousNumber = $surahChoices.SelectedItem.Number
    $query = Get-SurahSearchText $settingsWindow.FindName('SurahSearch').Text
    $surahChoices.Items.Clear()
    foreach ($verse in $verses) {
        if ($verse.ayah -ne 1) { continue }
        $label = $verse.surah_number.ToString() + ' · ' + $verse.surah_name
        if ((Get-SurahSearchText $label).Contains($query)) {
            $surahChoices.Items.Add([pscustomobject]@{ Label = $label; Number = $verse.surah_number }) | Out-Null
        }
    }
    $surahChoices.SelectedIndex = 0
    foreach ($choice in $surahChoices.Items) {
        if ($choice.Number -eq $previousNumber) { $surahChoices.SelectedItem = $choice; break }
    }
    $settingsWindow.FindName('SearchStatus').Text = ''
    if ($surahChoices.Items.Count -eq 0) { $settingsWindow.FindName('SearchStatus').Text = 'مفيش سورة بالاسم ده. جرّب اسم تاني أو امسح البحث.' }
}
function Show-Settings {
    $expiry.Stop()
    $timer.Stop()
    $settingsWindow = New-SettingsWindow
    $settingsWindow.FindName('ImagePreview').Background = $window.FindName('BackgroundCard').Background
    $settingsWindow.FindName('Memorization').Add_Click({ Show-MemorizationSettings })
    $selection = @{ ImagePath = $null }
    $countChoices = $settingsWindow.FindName('VerseCount')
    foreach ($count in 1..20) {
        $countChoices.Items.Add([pscustomobject]@{ Label = ($count.ToString() + ' آية'); Count = $count }) | Out-Null
    }
    $countChoices.SelectedIndex = $script:versesPerReminder - 1
    $settingsWindow.FindName('ShowTranslation').IsChecked = $script:showTranslation
    $surahChoices = $settingsWindow.FindName('Surah')
    foreach ($verse in $verses) {
        if ($verse.ayah -eq 1) {
            $surahChoices.Items.Add([pscustomobject]@{ Label = ($verse.surah_number.ToString() + ' · ' + $verse.surah_name); Number = $verse.surah_number }) | Out-Null
        }
    }
    $surahChoices.Add_SelectionChanged({ Update-AyahChoices $settingsWindow })
    $surahChoices.SelectedIndex = [int]$verses[[Math]::Min($script:currentIndex, $verses.Count - 1)].surah_number - 1
    $settingsWindow.FindName('Ayah').SelectedIndex = [int]$verses[[Math]::Min($script:currentIndex, $verses.Count - 1)].ayah - 1
    $settingsWindow.FindName('SurahSearch').Add_TextChanged({ Search-Surahs $settingsWindow })
    $settingsWindow.FindName('ChangeStart').Add_Click({
        $surahChoices.IsEnabled = $settingsWindow.FindName('ChangeStart').IsChecked
        $settingsWindow.FindName('Ayah').IsEnabled = $surahChoices.IsEnabled
        $settingsWindow.FindName('SurahSearch').IsEnabled = $surahChoices.IsEnabled
    })
    $settingsWindow.FindName('ChooseImage').Add_Click({
        $picker = [Microsoft.Win32.OpenFileDialog]::new()
        $picker.Filter = 'Images|*.png;*.jpg;*.jpeg;*.bmp;*.gif'
        if ($picker.ShowDialog($settingsWindow)) {
            try {
                $previewBrush = [Windows.Media.ImageBrush]::new((Get-BackgroundImage $picker.FileName))
                $previewBrush.Stretch = [Windows.Media.Stretch]::UniformToFill
                $settingsWindow.FindName('ImagePreview').Background = $previewBrush
                $selection.ImagePath = $picker.FileName
                $settingsWindow.FindName('ImageName').Text = [IO.Path]::GetFileName($picker.FileName)
            } catch { [Windows.MessageBox]::Show($settingsWindow, 'اختَر صورة سليمة بصيغة PNG أو JPG أو BMP أو GIF.', 'تعذر فتح الصورة') | Out-Null }
        }
    })
    $settingsWindow.FindName('Cancel').Add_Click({ $settingsWindow.Close() })
    $settingsWindow.FindName('Apply').Add_Click({
        try {
            if ($settingsWindow.FindName('ChangeStart').IsChecked -and $null -eq $settingsWindow.FindName('Ayah').SelectedItem) { throw 'اختَر سورة وآية صحيحة قبل الحفظ.' }
            Save-DisplayPreferences @{ verses_per_reminder = $countChoices.SelectedItem.Count; show_translation = [bool]$settingsWindow.FindName('ShowTranslation').IsChecked }
            if ($selection.ImagePath) { Set-CustomBackground $selection.ImagePath }
            if ($settingsWindow.FindName('ChangeStart').IsChecked) {
                Set-StartingVerse $settingsWindow.FindName('Ayah').SelectedItem.Index
            }
            $settingsWindow.Close()
        } catch { [Windows.MessageBox]::Show($settingsWindow, $_.Exception.Message, 'تعذر حفظ الإعدادات') | Out-Null }
    })
    $settingsWindow.ShowDialog() | Out-Null
    Show-Verse
}
