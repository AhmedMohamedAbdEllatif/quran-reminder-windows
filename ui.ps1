function Initialize-WindowStyle($targetWindow) {
    [xml]$resourcesMarkup = Get-Content (Join-Path $PSScriptRoot 'ui.xaml') -Raw -Encoding UTF8
    $sharedResources = [Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($resourcesMarkup))
    $targetWindow.Resources.MergedDictionaries.Add($sharedResources)
    $targetWindow.FontFamily = [Windows.Media.FontFamily]::new('Segoe UI')
}
