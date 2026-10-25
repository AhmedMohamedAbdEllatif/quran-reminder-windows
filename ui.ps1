function Initialize-WindowStyle($targetWindow) {
    [xml]$resourcesMarkup = Get-Content (Join-Path $PSScriptRoot 'ui.xaml') -Raw -Encoding UTF8
    $sharedResources = [Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($resourcesMarkup))
    $targetWindow.Resources.MergedDictionaries.Add($sharedResources)
    $targetWindow.FontFamily = [Windows.Media.FontFamily]::new('Segoe UI')
}
function New-SaveConfirmationWindow {
    [xml]$markup = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Width="440" Height="126"
 WindowStyle="None" ResizeMode="NoResize" AllowsTransparency="True" Background="Transparent"
 Topmost="True" ShowActivated="False" ShowInTaskbar="False" FlowDirection="RightToLeft" Title="تم حفظ الخطة">
 <Border Margin="10" Background="#F4F8F9" BorderBrush="#C7DBE1" BorderThickness="1" CornerRadius="16" Padding="20,18">
  <Border.Effect><DropShadowEffect Color="#193E49" BlurRadius="16" ShadowDepth="3" Opacity="0.18"/></Border.Effect>
  <Grid>
   <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
   <Border Width="42" Height="42" Background="#24596A" CornerRadius="21" VerticalAlignment="Center" Margin="0,0,16,0">
    <TextBlock Text="✓" Foreground="White" FontSize="25" HorizontalAlignment="Center" VerticalAlignment="Center"/>
   </Border>
   <StackPanel Grid.Column="1" VerticalAlignment="Center">
    <TextBlock Name="ConfirmationTitle" Text="تم حفظ الخطة" Foreground="#193E49" FontSize="18" FontWeight="SemiBold"/>
    <TextBlock Name="ConfirmationMessage" Text="إعدادات الحفظ والمراجعة اتحفظت." Foreground="#607D86" FontSize="14" Margin="0,5,0,0" TextWrapping="Wrap"/>
   </StackPanel>
  </Grid>
 </Border>
</Window>
'@
    $toast = [Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($markup))
    Initialize-WindowStyle $toast
    return $toast
}
function Get-IntervalLabel($seconds) {
    if ($seconds % 3600 -eq 0) { return (($seconds / 3600).ToString() + ' ساعة') }
    if ($seconds % 60 -eq 0) { return (($seconds / 60).ToString() + ' دقيقة') }
    return ($seconds.ToString() + ' ثانية')
}
function Show-SaveConfirmation($title, $message) {
    if ($script:saveConfirmation) { $script:saveConfirmation.Close() }
    $script:saveConfirmation = New-SaveConfirmationWindow
    $script:saveConfirmation.Title = $title
    $script:saveConfirmation.FindName('ConfirmationTitle').Text = $title
    $script:saveConfirmation.FindName('ConfirmationMessage').Text = $message
    $area = [Windows.SystemParameters]::WorkArea
    $script:saveConfirmation.Width = [Math]::Min(440, $area.Width - 36)
    $script:saveConfirmation.Left = $area.Right - $script:saveConfirmation.Width - 18
    $script:saveConfirmation.Top = $area.Bottom - $script:saveConfirmation.Height - 18
    $timer = [Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [TimeSpan]::FromSeconds(4)
    $timer.Tag = $script:saveConfirmation
    $script:saveConfirmation.Tag = $timer
    $timer.Add_Tick({ param($sender, $eventArgs) $sender.Stop(); $sender.Tag.Close() })
    $script:saveConfirmation.Add_Closed({ param($sender, $eventArgs) $sender.Tag.Stop() })
    $script:saveConfirmation.Show()
    $script:saveConfirmation.BeginAnimation([Windows.UIElement]::OpacityProperty, [Windows.Media.Animation.DoubleAnimation]::new(0, 1, [Windows.Duration]::new([TimeSpan]::FromMilliseconds(180))))
    $timer.Start()
}

function Resize-ReminderSurface($targetWindow, $contentScroll) {
    $area = [Windows.SystemParameters]::WorkArea
    $targetWindow.Width = [Math]::Min(1040, $area.Width - 48)
    $content = $contentScroll.Content
    $content.InvalidateMeasure()
    $content.Measure([Windows.Size]::new($targetWindow.Width - 82, [double]::PositiveInfinity))
    $requiredHeight = [Math]::Ceiling($content.DesiredSize.Height) + 214
    $targetWindow.Height = [Math]::Min($area.Height - 48, [Math]::Max(540, $requiredHeight))
    $content.InvalidateMeasure()
    $contentScroll.InvalidateMeasure()
    $targetWindow.Left = $area.Left + ($area.Width - $targetWindow.Width) / 2
    $targetWindow.Top = $area.Top + ($area.Height - $targetWindow.Height) / 2
}
