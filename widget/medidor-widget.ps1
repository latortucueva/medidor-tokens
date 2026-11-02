# Medidor de tokens - widget flotante de escritorio (La Tortucueva)
# Lee %USERPROFILE%\.claude\medidor-tokens.json, que escribe el plugin medidor-tokens de Claude Code.
# Diseño adaptable: horizontal (ancho), vertical (alto) o compacto (chico); todo escala con la ventana.
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$archivo = Join-Path $env:USERPROFILE '.claude\medidor-tokens.json'

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:shell="clr-namespace:System.Windows.Shell;assembly=PresentationFramework"
        Title="Medidor Claude" Width="300" Height="125" MinWidth="120" MinHeight="70"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="True" ResizeMode="CanResize">
  <shell:WindowChrome.WindowChrome>
    <shell:WindowChrome ResizeBorderThickness="7" CaptionHeight="0" CornerRadius="10" GlassFrameThickness="0" UseAeroCaptionButtons="False"/>
  </shell:WindowChrome.WindowChrome>
  <Border CornerRadius="10" Background="#F209090B" BorderBrush="#00FF66" BorderThickness="1" Padding="8">
    <Viewbox x:Name="Escala" Stretch="Uniform" StretchDirection="Both">
      <StackPanel x:Name="Raiz"/>
    </Viewbox>
  </Border>
</Window>
'@

$ventana = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$raiz = $ventana.FindName('Raiz')
$area = [System.Windows.SystemParameters]::WorkArea
$ventana.Left = $area.Right - 316
$ventana.Top = $area.Bottom - 160

$conv = New-Object System.Windows.Media.BrushConverter
function Pincel($hex) { $conv.ConvertFromString($hex) }
$MONO = 'JetBrains Mono, Consolas'
$VERDE = '#00FF66'; $NARANJA = '#FF4500'; $BLANCO = '#FAFAFA'; $GRIS = '#71717A'; $GRIS2 = '#A1A1AA'; $PISTA = '#27272A'

function Texto($txt, $color, $tam, $negrita = $false) {
  $t = New-Object System.Windows.Controls.TextBlock
  $t.Text = $txt; $t.Foreground = Pincel $color; $t.FontFamily = $MONO; $t.FontSize = $tam
  if ($negrita) { $t.FontWeight = 'Bold' }
  $t
}

function Barra($pct, $color, $alto) {
  $v = [Math]::Max(0.0, [Math]::Min(100.0, [double]$pct))
  $g = New-Object System.Windows.Controls.Grid
  $g.Height = $alto; $g.VerticalAlignment = 'Center'
  $track = New-Object System.Windows.Controls.Border
  $track.CornerRadius = $alto / 2; $track.Background = Pincel $PISTA
  [void]$g.Children.Add($track)
  $r = New-Object System.Windows.Controls.Grid
  foreach ($w in $v, (100 - $v)) {
    $c = New-Object System.Windows.Controls.ColumnDefinition
    $c.Width = [System.Windows.GridLength]::new([Math]::Max($w, 0.001), 'Star')
    $r.ColumnDefinitions.Add($c)
  }
  $b = New-Object System.Windows.Controls.Border
  $b.CornerRadius = $alto / 2; $b.Background = Pincel $color
  [void]$r.Children.Add($b)
  [void]$g.Children.Add($r)
  $g
}

function Boton($txt, $tip, $accion) {
  $t = Texto $txt $GRIS2 11
  $t.Cursor = 'Hand'; $t.ToolTip = $tip; $t.Margin = '8,0,0,0'; $t.Tag = 'boton'
  $t.Add_MouseLeftButtonUp($accion)
  $t
}

function Cabecera($ancho, $edad, $chico) {
  $g = New-Object System.Windows.Controls.Grid
  $g.Width = $ancho; $g.Margin = '0,0,0,6'
  $titulo = if ($chico) { 'CLAUDE' } else { 'CLAUDE · USO' }
  [void]$g.Children.Add((Texto $titulo $VERDE 11 $true))
  $d = New-Object System.Windows.Controls.StackPanel
  $d.Orientation = 'Horizontal'; $d.HorizontalAlignment = 'Right'
  if ($edad -and -not $chico) { $e = Texto $edad $GRIS 10; $e.Margin = '0,1,2,0'; [void]$d.Children.Add($e) }
  [void]$d.Children.Add((Boton '–' 'Minimizar' { $ventana.WindowState = 'Minimized' }))
  [void]$d.Children.Add((Boton '✕' 'Cerrar' { $ventana.Close() }))
  [void]$g.Children.Add($d)
  $g
}

$dias = 'dom', 'lun', 'mar', 'mié', 'jue', 'vie', 'sáb'
function Renueva($iso, $corto) {
  if (-not $iso) { return $null }
  try { $f = [DateTime]::Parse($iso).ToLocalTime() } catch { return $null }
  $dia = if ($f.Date -eq (Get-Date).Date) { 'hoy' } else { "$($dias[[int]$f.DayOfWeek]) $($f.Day)/$($f.Month)" }
  if ($corto) { "$dia $($f.ToString('HH:mm'))" } else { "se renueva $dia $($f.ToString('HH:mm'))" }
}

function Metricas($m) {
  $out = @()
  $pct = $m.percent
  if ($null -eq $pct -and $m.tokens -and $m.window) { $pct = $m.tokens / $m.window * 100 }
  if ($null -ne $pct) {
    $k = { param($n) if ($n -ge 1000) { "$([Math]::Round($n / 1000))k" } else { "$n" } }
    $out += [pscustomobject]@{ n = 'Ctx'; largo = 'Contexto'; pct = $pct; iso = $null; extra = $(if ($m.tokens) { "$(& $k $m.tokens) / $(& $k $m.window)" }) }
  }
  foreach ($l in $m.limits) {
    $n = switch ($l.kind) { 'five_hour' { '5 h' } 'seven_day' { 'Sem' } default { $l.kind } }
    $largo = switch ($l.kind) { 'five_hour' { 'Límite 5 h' } 'seven_day' { 'Semana' } default { $l.kind } }
    $out += [pscustomobject]@{ n = $n; largo = $largo; pct = $l.percentUsed; iso = $l.resetsAt; extra = $null }
  }
  $out
}

# Horizontal: filas con barra larga (ventanas anchas)
function DisenoHorizontal($ms, $edad) {
  $W = 280
  [void]$raiz.Children.Add((Cabecera $W $edad $false))
  foreach ($x in $ms) {
    $col = if ($x.pct -ge 80) { $NARANJA } else { $VERDE }
    $g = New-Object System.Windows.Controls.Grid
    $g.Width = $W; $g.Margin = '0,3,0,0'
    foreach ($w in 50, 0, 44) {
      $c = New-Object System.Windows.Controls.ColumnDefinition
      $c.Width = if ($w -eq 0) { [System.Windows.GridLength]::new(1, 'Star') } else { [System.Windows.GridLength]::new($w) }
      $g.ColumnDefinitions.Add($c)
    }
    [void]$g.Children.Add((Texto $x.n $BLANCO 11))
    $b = Barra $x.pct $col 7; $b.Margin = '0,0,6,0'
    [System.Windows.Controls.Grid]::SetColumn($b, 1); [void]$g.Children.Add($b)
    $p = Texto "$([Math]::Round($x.pct))%" $col 11 $true; $p.HorizontalAlignment = 'Right'
    [System.Windows.Controls.Grid]::SetColumn($p, 2); [void]$g.Children.Add($p)
    [void]$raiz.Children.Add($g)
    $det = if ($x.iso) { Renueva $x.iso $false } else { $x.extra }
    if ($det) { $d = Texto $det $GRIS 9.5; $d.Margin = '50,0,0,1'; [void]$raiz.Children.Add($d) }
  }
}

# Vertical: tarjetas apiladas con el porcentaje grande (ventanas altas)
function DisenoVertical($ms, $edad) {
  $W = 160
  [void]$raiz.Children.Add((Cabecera $W $edad $true))
  foreach ($x in $ms) {
    $col = if ($x.pct -ge 80) { $NARANJA } else { $VERDE }
    $card = New-Object System.Windows.Controls.Border
    $card.Width = $W; $card.Margin = '0,4,0,4'; $card.Padding = '10,8,10,9'
    $card.CornerRadius = 8; $card.Background = Pincel '#18181B'; $card.BorderBrush = Pincel $PISTA; $card.BorderThickness = 1
    $s = New-Object System.Windows.Controls.StackPanel
    [void]$s.Children.Add((Texto $x.largo.ToUpper() $GRIS2 10 $true))
    $big = Texto "$([Math]::Round($x.pct))%" $col 30 $true; $big.Margin = '0,2,0,4'
    [void]$s.Children.Add($big)
    [void]$s.Children.Add((Barra $x.pct $col 6))
    $det = if ($x.iso) { Renueva $x.iso $false } else { $x.extra }
    if ($det) { $d = Texto $det $GRIS 9; $d.Margin = '0,5,0,0'; [void]$s.Children.Add($d) }
    $card.Child = $s
    [void]$raiz.Children.Add($card)
  }
  if ($edad) { $e = Texto "act. $edad" $GRIS 9; $e.HorizontalAlignment = 'Center'; $e.Margin = '0,2,0,0'; [void]$raiz.Children.Add($e) }
}

# Compacto: una sola línea con los números (ventanas chicas o muy anchas y bajas)
function DisenoCompacto($ms) {
  $s = New-Object System.Windows.Controls.StackPanel
  $s.Orientation = 'Horizontal'
  [void]$s.Children.Add((Texto 'CLAUDE ' $VERDE 12 $true))
  foreach ($x in $ms) {
    $col = if ($x.pct -ge 80) { $NARANJA } else { $VERDE }
    $a = Texto "  $($x.n) " $GRIS2 12; [void]$s.Children.Add($a)
    [void]$s.Children.Add((Texto "$([Math]::Round($x.pct))%" $col 12 $true))
  }
  [void]$s.Children.Add((Boton '–' 'Minimizar' { $ventana.WindowState = 'Minimized' }))
  [void]$s.Children.Add((Boton '✕' 'Cerrar' { $ventana.Close() }))
  [void]$raiz.Children.Add($s)
}

function Modo {
  $w = $ventana.ActualWidth; $h = $ventana.ActualHeight
  if ($w -le 0) { $w = $ventana.Width; $h = $ventana.Height }
  $r = $w / $h
  if ($h -lt 85 -or $r -gt 4) { 'compacto' } elseif ($r -lt 1.15) { 'vertical' } else { 'horizontal' }
}

$script:ultimo = ''
function Actualizar([bool]$forzar = $false) {
  $modo = Modo
  $datos = if (Test-Path $archivo) { Get-Content $archivo -Raw -Encoding UTF8 } else { '' }
  $min = $null
  if ($datos) { try { $m = $datos | ConvertFrom-Json; $min = [Math]::Floor(((Get-Date) - [DateTime]::Parse($m.updatedAt).ToLocalTime()).TotalMinutes) } catch {} }
  $firma = "$modo|$datos|$min"
  if (-not $forzar -and $firma -eq $script:ultimo) { return }
  $script:ultimo = $firma
  $raiz.Children.Clear()
  if (-not $datos) {
    [void]$raiz.Children.Add((Cabecera 220 $null $false))
    [void]$raiz.Children.Add((Texto "Sin datos todavía.`nAbrí Claude Code y mandá un mensaje." $GRIS2 10.5))
    return
  }
  $edad = if ($null -eq $min) { $null } elseif ($min -lt 1) { 'ahora' } elseif ($min -lt 60) { "hace $min min" } else { "hace $([Math]::Floor($min / 60)) h" }
  $ms = Metricas $m
  switch ($modo) {
    'vertical' { DisenoVertical $ms $edad }
    'compacto' { DisenoCompacto $ms }
    default { DisenoHorizontal $ms $edad }
  }
}

$ventana.Add_MouseLeftButtonDown({ param($s, $e)
  if ($e.OriginalSource.Tag -ne 'boton' -and $e.ButtonState -eq 'Pressed') { try { $ventana.DragMove() } catch {} } })
$ventana.Add_StateChanged({ if ($ventana.WindowState -eq 'Normal') { $ventana.Topmost = $true } })
$ventana.Add_SizeChanged({ Actualizar })

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(3)
$timer.Add_Tick({ Actualizar })
$timer.Start()
$ventana.Add_ContentRendered({ Actualizar $true })
[void]$ventana.ShowDialog()
