$fontDirectory = [Uri]::new($PSScriptRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar)
$script:ayahMarkerFont = [Windows.Media.FontFamily]::new($fontDirectory, './AmiriQuran.ttf#Amiri Quran')
function Get-ArabicVerseNumber($number) {
    return -join ($number.ToString([Globalization.CultureInfo]::InvariantCulture).ToCharArray() | ForEach-Object { [char](0x0660 + [int]::Parse($_.ToString())) })
}
$markerTypeface = [Windows.Media.Typeface]::new($script:ayahMarkerFont, [Windows.FontStyles]::Normal, [Windows.FontWeights]::Normal, [Windows.FontStretches]::Normal)
$markerGlyphs = $null
if (-not $markerTypeface.TryGetGlyphTypeface([ref]$markerGlyphs) -or $markerGlyphs.FontUri.LocalPath -ne (Join-Path $PSScriptRoot 'AmiriQuran.ttf') -or -not $markerGlyphs.CharacterToGlyphMap.ContainsKey([char]0x06DD)) { throw 'Bundled Quran marker font is unavailable.' }
$script:ayahOrnament = $markerGlyphs.GetGlyphOutline($markerGlyphs.CharacterToGlyphMap[0x06DD], 40, 40)
$script:ayahOrnament.Freeze()
function New-AyahNumberLabel($digits, $size, $foreground) {
    $number = [Windows.Controls.TextBlock]::new()
    $number.Text = $digits
    $number.FontFamily = [Windows.Media.FontFamily]::new('Segoe UI')
    $factor = if ($digits.Length -ge 3) { 0.36 } else { 0.42 }
    $number.FontSize = $size * $factor
    $number.Foreground = $foreground
    $number.FlowDirection = [Windows.FlowDirection]::LeftToRight
    $number.HorizontalAlignment = [Windows.HorizontalAlignment]::Center
    $number.VerticalAlignment = [Windows.VerticalAlignment]::Center
    return $number
}
function Add-AyahMarker($label, $digits) {
    $seal = [Windows.Controls.Grid]::new()
    $seal.Width = $label.FontSize; $seal.Height = $label.FontSize
    $seal.Tag = $digits
    [Windows.Automation.AutomationProperties]::SetName($seal, ('الآية ' + $digits))
    $outline = [Windows.Shapes.Path]::new()
    $outline.Data = $script:ayahOrnament
    $outline.Stretch = [Windows.Media.Stretch]::Uniform
    $outline.Fill = $label.Foreground
    $seal.Children.Add($outline) | Out-Null
    $seal.Children.Add((New-AyahNumberLabel $digits $label.FontSize $label.Foreground)) | Out-Null
    $label.Inlines.Add([Windows.Documents.InlineUIContainer]::new($seal))
}
function Set-ReadingVerse($label, $verse) {
    $label.Inlines.Clear()
    $label.Inlines.Add([Windows.Documents.Run]::new($verse.arabic))
    $label.Inlines.Add([Windows.Documents.Run]::new(' '))
    Add-AyahMarker $label (Get-ArabicVerseNumber ([int]$verse.ayah))
}
function Set-MushafLine($label, $text) {
    $label.Inlines.Clear()
    $cursor = 0
    foreach ($number in [regex]::Matches($text, '[٠-٩]+')) {
        if ($number.Index -gt $cursor) { $label.Inlines.Add([Windows.Documents.Run]::new($text.Substring($cursor, $number.Index - $cursor))) }
        Add-AyahMarker $label $number.Value
        $cursor = $number.Index + $number.Length
    }
    if ($cursor -lt $text.Length) { $label.Inlines.Add([Windows.Documents.Run]::new($text.Substring($cursor))) }
}
