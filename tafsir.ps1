function New-TafsirWindow {
    [xml]$tafsirLayout = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="التفسير الميسر"
 Width="900" Height="680" MinWidth="420" MinHeight="350" WindowStartupLocation="CenterScreen"
 Topmost="True" Background="#F4F8F9" Foreground="#193E49" FlowDirection="RightToLeft" FontFamily="Segoe UI">
 <Grid Margin="28">
  <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
  <StackPanel Margin="0,0,0,20">
   <TextBlock Text="التفسير الميسر" FontSize="25" FontWeight="SemiBold"/>
   <TextBlock Text="تفسير الآيات المعروضة في التذكير الحالي" FontSize="14" Foreground="#607D86" Margin="0,6,0,0"/>
  </StackPanel>
  <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
   <StackPanel Name="TafsirContent"/>
  </ScrollViewer>
  <Button Name="Close" Grid.Row="2" Content="العودة للآيات" Background="#24596A" Foreground="White" IsCancel="True" FontSize="16" Padding="28,11" Margin="0,22,0,0" HorizontalAlignment="Center"/>
 </Grid>
</Window>
'@
    $tafsirWindow = [Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($tafsirLayout))
    Initialize-WindowStyle $tafsirWindow
    $tafsirWindow.Width = [Math]::Min(900, [Windows.SystemParameters]::WorkArea.Width - 48)
    $tafsirWindow.Height = [Math]::Min(680, [Windows.SystemParameters]::WorkArea.Height - 48)
    for ($offset = 0; $offset -lt $script:displayedCount; $offset++) {
        Add-TafsirPanel $tafsirWindow $verses[$script:currentIndex + $offset]
    }
    return $tafsirWindow
}
function Add-TafsirPanel($tafsirWindow, $verse) {
    $section = [Windows.Controls.StackPanel]::new()
    $section.Margin = [Windows.Thickness]::new(0, 0, 0, 24)
    $heading = [Windows.Controls.TextBlock]::new()
    $heading.Text = $verse.surah_name + ' · الآية ' + $verse.ayah
    $heading.FontSize = 17
    $heading.FontWeight = [Windows.FontWeights]::SemiBold
    $heading.Margin = [Windows.Thickness]::new(0, 0, 0, 10)
    $meaning = [Windows.Controls.TextBlock]::new()
    $meaning.Text = $verse.tafsir
    $meaning.FontSize = 20
    $meaning.LineHeight = 36
    $meaning.TextWrapping = [Windows.TextWrapping]::Wrap
    $section.Children.Add($heading) | Out-Null
    $section.Children.Add($meaning) | Out-Null
    $tafsirWindow.FindName('TafsirContent').Children.Add($section) | Out-Null
}
function Show-Tafsir {
    if ($script:displayedCount -eq 0) { return }
    $expiry.Stop()
    $timer.Stop()
    $tafsirWindow = New-TafsirWindow
    $tafsirWindow.FindName('Close').Add_Click({ $tafsirWindow.Close() })
    $tafsirWindow.ShowDialog() | Out-Null
    Show-Verse
}
