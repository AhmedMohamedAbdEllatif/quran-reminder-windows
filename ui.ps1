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
    <TextBlock Text="تم حفظ الخطة" Foreground="#193E49" FontSize="18" FontWeight="SemiBold"/>
    <TextBlock Text="إعدادات الحفظ والمراجعة اتحفظت." Foreground="#607D86" FontSize="14" Margin="0,5,0,0" TextWrapping="Wrap"/>
   </StackPanel>
  </Grid>
 </Border>
</Window>
'@
    $toast = [Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($markup))
    Initialize-WindowStyle $toast
    return $toast
}
function Show-SaveConfirmation {
    if ($script:saveConfirmation) { $script:saveConfirmation.Close() }
    $script:saveConfirmation = New-SaveConfirmationWindow
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
