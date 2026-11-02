# Medidor de tokens - widget flotante de escritorio (La Tortucueva)
# Lee %USERPROFILE%\.claude\medidor-tokens.json, que escribe el plugin medidor-tokens de Claude Code.
# Diseño adaptable inspirado en el mini reproductor de Spotify:
#   bajo        -> tira (logo, título y más datos a medida que se ensancha)
#   medio       -> tira + fila de barras
#   alto        -> indicador circular grande + detalle de cada límite
# OJO: en PowerShell las variables no distinguen mayúsculas; no reutilizar nombres de constantes.
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$archivo = Join-Path $env:USERPROFILE '.claude\medidor-tokens.json'
$logo = Join-Path $PSScriptRoot 'logo.png'

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:shell="clr-namespace:System.Windows.Shell;assembly=PresentationFramework"
        Title="Medidor Claude" Width="300" Height="58" MinWidth="170" MinHeight="58"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="True" ResizeMode="CanResize">
  <shell:WindowChrome.WindowChrome>
    <shell:WindowChrome ResizeBorderThickness="7" CaptionHeight="0" CornerRadius="10" GlassFrameThickness="0" UseAeroCaptionButtons="False"/>
  </shell:WindowChrome.WindowChrome>
  <Border x:Name="Marco" CornerRadius="10" Background="#F20B0F0D" BorderBrush="#2A2A2E" BorderThickness="1" ClipToBounds="True">
    <Grid>
      <Grid x:Name="Raiz" Margin="9,8,9,8"/>
      <Grid x:Name="Linea" Height="2" VerticalAlignment="Bottom" Margin="10,0,10,1"/>
      <Grid x:Name="Chrome" VerticalAlignment="Top" Height="20" Margin="8,3,8,0" Visibility="Collapsed"/>
      <TextBlock x:Name="Grip" Text="◢" Foreground="#3F3F46" FontSize="9" HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,0,3,2" Visibility="Collapsed" IsHitTestVisible="False"/>
    </Grid>
  </Border>
</Window>
'@

$ventana = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$raiz = $ventana.FindName('Raiz'); $marco = $ventana.FindName('Marco')
$linea = $ventana.FindName('Linea'); $chrome = $ventana.FindName('Chrome'); $grip = $ventana.FindName('Grip')
$area = [System.Windows.SystemParameters]::WorkArea
$ventana.Left = $area.Right - 316; $ventana.Top = $area.Bottom - 74

$conv = New-Object System.Windows.Media.BrushConverter
function Pincel($hex) { $conv.ConvertFromString($hex) }
$FUENTE_MONO = 'JetBrains Mono, Consolas'; $FUENTE_UI = 'Segoe UI Semibold, Segoe UI'
$C_VERDE = '#00FF66'; $C_NARANJA = '#FF4500'; $C_BLANCO = '#FAFAFA'; $C_GRIS = '#71717A'; $C_GRIS2 = '#A1A1AA'; $C_PISTA = '#27272A'; $C_TARJ = '#121815'

function Texto($txt, $color, $tam, $negrita = $false, $fuente = $FUENTE_MONO) {
  $t = New-Object System.Windows.Controls.TextBlock
  $t.Text = $txt; $t.Foreground = Pincel $color; $t.FontFamily = $fuente; $t.FontSize = $tam
  $t.TextTrimming = 'CharacterEllipsis'
  if ($negrita) { $t.FontWeight = 'Bold' }
  $t
}
function Colocar($el, $col = 0, $fila = 0) { [System.Windows.Controls.Grid]::SetColumn($el, $col); [System.Windows.Controls.Grid]::SetRow($el, $fila); $el }
function Cols($grid, $defs) {
  foreach ($w in $defs) {
    $c = New-Object System.Windows.Controls.ColumnDefinition
    $c.Width = if ("$w" -eq '*') { [System.Windows.GridLength]::new(1, 'Star') } elseif ("$w" -eq 'a') { [System.Windows.GridLength]::Auto } else { [System.Windows.GridLength]::new([double]$w) }
    $grid.ColumnDefinitions.Add($c)
  }
}
function Filas($grid, $defs) {
  foreach ($h in $defs) {
    $r = New-Object System.Windows.Controls.RowDefinition
    $r.Height = if ("$h" -eq '*') { [System.Windows.GridLength]::new(1, 'Star') } elseif ("$h" -eq 'a') { [System.Windows.GridLength]::Auto } else { [System.Windows.GridLength]::new([double]$h) }
    $grid.RowDefinitions.Add($r)
  }
}

function Barra($pct, $color, $alto) {
  $v = [Math]::Max(0.0, [Math]::Min(100.0, [double]$pct))
  $g = New-Object System.Windows.Controls.Grid
  $g.Height = $alto; $g.VerticalAlignment = 'Center'
  $track = New-Object System.Windows.Controls.Border
  $track.CornerRadius = $alto / 2; $track.Background = Pincel $C_PISTA
  [void]$g.Children.Add($track)
  $r = New-Object System.Windows.Controls.Grid
  Cols $r @(1, 1)
  $r.ColumnDefinitions[0].Width = [System.Windows.GridLength]::new([Math]::Max($v, 0.001), 'Star')
  $r.ColumnDefinitions[1].Width = [System.Windows.GridLength]::new([Math]::Max(100 - $v, 0.001), 'Star')
  $fill = New-Object System.Windows.Controls.Border
  $fill.CornerRadius = $alto / 2; $fill.Background = Pincel $color
  [void]$r.Children.Add($fill)
  [void]$g.Children.Add($r)
  $g
}

# Indicador circular (en el lugar de la tapa del disco)
function Anillo($pct, $color, $tam, $etiqueta) {
  $v = [Math]::Max(0.0, [Math]::Min(99.99, [double]$pct))
  $grosor = [Math]::Max(6, $tam * 0.075)
  $rad = ($tam - $grosor) / 2; $cx = $tam / 2; $cy = $tam / 2
  $cv = New-Object System.Windows.Controls.Grid
  $cv.Width = $tam; $cv.Height = $tam
  $fondoA = New-Object System.Windows.Shapes.Ellipse
  $fondoA.Width = $tam - $grosor; $fondoA.Height = $tam - $grosor; $fondoA.Stroke = Pincel $C_PISTA; $fondoA.StrokeThickness = $grosor
  [void]$cv.Children.Add($fondoA)
  if ($v -gt 0) {
    $ang = $v / 100 * 2 * [Math]::PI
    $x = $cx + $rad * [Math]::Sin($ang); $y = $cy - $rad * [Math]::Cos($ang)
    $grande = if ($v -gt 50) { 1 } else { 0 }
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $d = [string]::Format($inv, 'M {0},{1} A {2},{2} 0 {3} 1 {4},{5}', $cx, ($cy - $rad), $rad, $grande, $x, $y)
    $arco = New-Object System.Windows.Shapes.Path
    $arco.Data = [System.Windows.Media.Geometry]::Parse($d)
    $arco.Stroke = Pincel $color; $arco.StrokeThickness = $grosor
    $arco.StrokeStartLineCap = 'Round'; $arco.StrokeEndLineCap = 'Round'
    $arco.Effect = New-Object System.Windows.Media.Effects.DropShadowEffect -Property @{ Color = [System.Windows.Media.ColorConverter]::ConvertFromString($color); BlurRadius = 14; ShadowDepth = 0; Opacity = 0.55 }
    [void]$cv.Children.Add($arco)
  }
  $centro = New-Object System.Windows.Controls.StackPanel
  $centro.HorizontalAlignment = 'Center'; $centro.VerticalAlignment = 'Center'
  $n = Texto "$([Math]::Round([double]$pct))%" $C_BLANCO ([Math]::Max(14, $tam * 0.2)) $true; $n.HorizontalAlignment = 'Center'
  [void]$centro.Children.Add($n)
  $e = Texto $etiqueta $C_GRIS2 ([Math]::Max(9, $tam * 0.065)); $e.HorizontalAlignment = 'Center'
  [void]$centro.Children.Add($e)
  [void]$cv.Children.Add($centro)
  $cv
}

function Boton($txt, $tip, $accion, $tam = 12) {
  $t = Texto $txt $C_GRIS2 $tam
  $t.Cursor = 'Hand'; $t.ToolTip = $tip; $t.Tag = 'boton'; $t.Margin = '9,0,0,0'
  $t.Add_MouseLeftButtonUp($accion)
  $t.Add_MouseEnter({ $this.Foreground = Pincel $C_BLANCO })
  $t.Add_MouseLeave({ $this.Foreground = Pincel $C_GRIS2 })
  $t
}
function Botones {
  $s = New-Object System.Windows.Controls.StackPanel
  $s.Orientation = 'Horizontal'; $s.VerticalAlignment = 'Center'
  [void]$s.Children.Add((Boton '–' 'Minimizar' { $ventana.WindowState = 'Minimized' } 15))
  [void]$s.Children.Add((Boton '✕' 'Cerrar' { $ventana.Close() } 12))
  $s
}
function Miniatura($tam) {
  $th = New-Object System.Windows.Controls.Border
  $th.Width = $tam; $th.Height = $tam; $th.CornerRadius = 6; $th.Background = Pincel '#102A1C'
  if (Test-Path $logo) {
    $img = New-Object System.Windows.Controls.Image
    $bm = New-Object System.Windows.Media.Imaging.BitmapImage
    $bm.BeginInit(); $bm.UriSource = [Uri]$logo; $bm.CacheOption = 'OnLoad'; $bm.EndInit()
    $img.Source = $bm; $img.Margin = '3'; $th.Child = $img
  } else { $c = Texto 'C' $C_VERDE ($tam * 0.45) $true; $c.HorizontalAlignment = 'Center'; $c.VerticalAlignment = 'Center'; $th.Child = $c }
  $th
}

$dias = 'dom', 'lun', 'mar', 'mié', 'jue', 'vie', 'sáb'
function Renueva($iso) {
  if (-not $iso) { return $null }
  try { $f = [DateTime]::Parse($iso).ToLocalTime() } catch { return $null }
  $dia = if ($f.Date -eq (Get-Date).Date) { 'hoy' } else { "$($dias[[int]$f.DayOfWeek]) $($f.Day)/$($f.Month)" }
  "$dia $($f.ToString('HH:mm'))"
}
function ColorDe($p) { if ($p -ge 80) { $C_NARANJA } else { $C_VERDE } }

function Metricas($m) {
  $out = @()
  foreach ($l in $m.limits) {
    $n = switch ($l.kind) { 'five_hour' { '5 h' } 'seven_day' { 'Sem' } default { $l.kind } }
    $largo = switch ($l.kind) { 'five_hour' { 'Límite 5 h' } 'seven_day' { 'Semana' } default { $l.kind } }
    $out += [pscustomobject]@{ n = $n; largo = $largo; pct = [double]$l.percentUsed; ren = (Renueva $l.resetsAt) }
  }
  $pct = $m.percent
  if ($null -eq $pct -and $m.tokens -and $m.window) { $pct = $m.tokens / $m.window * 100 }
  if ($null -ne $pct) {
    $k = { param($n) if ($n -ge 1000) { "$([Math]::Round($n / 1000))k" } else { "$n" } }
    $out += [pscustomobject]@{ n = 'Ctx'; largo = 'Contexto'; pct = [double]$pct; ren = $(if ($m.tokens) { "$(& $k $m.tokens) / $(& $k $m.window) tokens" }) }
  }
  $out
}

# ---------- tira (altura mínima) ----------
function Tira($ms, $edad, $W, $conBotones) {
  $g = New-Object System.Windows.Controls.Grid
  $g.Height = 40
  Cols $g @(40, '*', 'a', 'a')
  [void]$g.Children.Add((Miniatura 38))
  $info = New-Object System.Windows.Controls.StackPanel
  $info.VerticalAlignment = 'Center'; $info.Margin = '9,0,6,0'
  [void]$info.Children.Add((Texto 'Claude · uso' $C_BLANCO 13 $false $FUENTE_UI))
  if ($edad) { [void]$info.Children.Add((Texto "act. $edad" $C_GRIS2 10)) }
  [void]$g.Children.Add((Colocar $info 1))
  $libre = $W - 18 - 40 - 115 - $(if ($conBotones) { 50 } else { 0 })
  $detalle = $libre -ge 420
  $ancho = if ($detalle) { 140 } else { 64 }
  $cuantas = [Math]::Max(1, [Math]::Min($ms.Count, [Math]::Floor($libre / $ancho)))
  $sp = New-Object System.Windows.Controls.StackPanel
  $sp.Orientation = 'Horizontal'; $sp.VerticalAlignment = 'Center'
  foreach ($x in $ms[0..($cuantas - 1)]) {
    $col = ColorDe $x.pct
    $mm = New-Object System.Windows.Controls.StackPanel
    $mm.Margin = '10,0,4,0'; $mm.VerticalAlignment = 'Center'
    $f = New-Object System.Windows.Controls.StackPanel; $f.Orientation = 'Horizontal'
    [void]$f.Children.Add((Texto "$($x.n) " $C_GRIS2 10.5))
    [void]$f.Children.Add((Texto "$([Math]::Round($x.pct))%" $col 12 $true))
    [void]$mm.Children.Add($f)
    if ($detalle) {
      $b = Barra $x.pct $col 3; $b.Width = 120; $b.Margin = '0,3,0,2'; [void]$mm.Children.Add($b)
      if ($x.ren) { [void]$mm.Children.Add((Texto $x.ren $C_GRIS 9)) }
    }
    [void]$sp.Children.Add($mm)
  }
  [void]$g.Children.Add((Colocar $sp 2))
  if ($conBotones) { $bt = Botones; $bt.Margin = '6,0,0,0'; [void]$g.Children.Add((Colocar $bt 3)) }
  $g
}

# ---------- fila de barras (altura media) ----------
function FilaBarras($ms, $W) {
  $g = New-Object System.Windows.Controls.Grid
  $g.Margin = '0,10,0,0'
  $cuantas = [Math]::Max(1, [Math]::Min($ms.Count, [Math]::Floor(($W - 18) / 80)))
  Cols $g (@('*') * $cuantas)
  $i = 0
  foreach ($x in $ms[0..($cuantas - 1)]) {
    $col = ColorDe $x.pct
    $s = New-Object System.Windows.Controls.StackPanel
    $s.Margin = $(if ($i -eq 0) { '0,0,6,0' } else { '6,0,6,0' })
    $h = New-Object System.Windows.Controls.Grid; Cols $h @('*', 'a')
    [void]$h.Children.Add((Texto $x.n $C_GRIS2 10))
    [void]$h.Children.Add((Colocar (Texto "$([Math]::Round($x.pct))%" $col 11 $true) 1))
    [void]$s.Children.Add($h)
    $b = Barra $x.pct $col 4; $b.Margin = '0,4,0,0'; [void]$s.Children.Add($b)
    [void]$g.Children.Add((Colocar $s $i)); $i++
  }
  $g
}

# ---------- detalle (lista, como la fila de reproducción) ----------
function Detalle($ms, $maxAlto) {
  $s = New-Object System.Windows.Controls.StackPanel
  $s.Margin = '0,8,0,0'
  $sep = New-Object System.Windows.Controls.Grid; Cols $sep @('*', 'a', '*')
  foreach ($c in 0, 2) { $l = New-Object System.Windows.Controls.Border; $l.Height = 1; $l.Background = Pincel '#2A2A2E'; [void]$sep.Children.Add((Colocar $l $c)) }
  $tt = Texto ' DETALLE ' $C_GRIS 9; [void]$sep.Children.Add((Colocar $tt 1))
  [void]$s.Children.Add($sep)
  $usado = 22
  foreach ($x in $ms) {
    if ($usado + 40 -gt $maxAlto) { break }
    $col = ColorDe $x.pct
    $r = New-Object System.Windows.Controls.Grid; $r.Margin = '0,7,0,0'; Cols $r @('*', 'a')
    $iz = New-Object System.Windows.Controls.StackPanel
    [void]$iz.Children.Add((Texto $x.largo $C_BLANCO 12 $false $FUENTE_UI))
    $sub = if ($x.ren) { if ($x.n -eq 'Ctx') { $x.ren } else { "se renueva $($x.ren)" } } else { '' }
    [void]$iz.Children.Add((Texto $sub $C_GRIS 9.5))
    [void]$r.Children.Add($iz)
    $p = Texto "$([Math]::Round($x.pct))%" $col 13 $true; $p.VerticalAlignment = 'Center'
    [void]$r.Children.Add((Colocar $p 1))
    [void]$s.Children.Add($r)
    $b = Barra $x.pct $col 3; $b.Margin = '0,4,0,0'; [void]$s.Children.Add($b)
    $usado += 40
  }
  $s
}

# ---------- vista alta: anillo grande + título + detalle ----------
function Alto($ms, $edad, $W, $H) {
  $principal = $ms[0]
  $g = New-Object System.Windows.Controls.Grid
  $g.Margin = '0,14,0,0'
  $anchoUtil = $W - 18; $altoUtil = $H - 16 - 14
  $conDetalle = $altoUtil -ge 330 -and $ms.Count -gt 1
  $tam = [Math]::Min($anchoUtil - 20, $altoUtil - 62 - $(if ($conDetalle) { 30 + 40 * ($ms.Count - 1) } else { 0 }))
  $tam = [Math]::Max(70, [Math]::Min($tam, 260))
  $s = New-Object System.Windows.Controls.StackPanel
  $a = Anillo $principal.pct (ColorDe $principal.pct) $tam $principal.n; $a.HorizontalAlignment = 'Center'
  [void]$s.Children.Add($a)
  $t = New-Object System.Windows.Controls.Grid; $t.Margin = '2,10,0,0'; Cols $t @('*', 'a')
  $info = New-Object System.Windows.Controls.StackPanel
  [void]$info.Children.Add((Texto $principal.largo $C_BLANCO 16 $true $FUENTE_UI))
  $sub = if ($principal.ren) { "se renueva $($principal.ren)" } else { '' }
  if ($edad) { $sub = if ($sub) { "$sub · act. $edad" } else { "act. $edad" } }
  [void]$info.Children.Add((Texto $sub $C_GRIS2 10))
  [void]$t.Children.Add($info)
  [void]$s.Children.Add($t)
  if ($conDetalle) { [void]$s.Children.Add((Detalle @($ms | Select-Object -Skip 1) ($altoUtil - $tam - 60))) }
  [void]$g.Children.Add($s)
  $g
}

# ---------- vista alta y ancha: anillo a la izquierda, detalle a la derecha ----------
function AltoAncho($ms, $edad, $W, $H) {
  $g = New-Object System.Windows.Controls.Grid
  $g.Margin = '0,14,0,0'
  Cols $g @('a', '*')
  $tam = [Math]::Max(70, [Math]::Min($H - 16 - 14 - 10, 220))
  $iz = New-Object System.Windows.Controls.StackPanel; $iz.VerticalAlignment = 'Center'
  [void]$iz.Children.Add((Anillo $ms[0].pct (ColorDe $ms[0].pct) $tam $ms[0].n))
  [void]$g.Children.Add($iz)
  $de = New-Object System.Windows.Controls.StackPanel; $de.Margin = '16,0,0,0'; $de.VerticalAlignment = 'Center'
  [void]$de.Children.Add((Texto 'Claude · uso' $C_BLANCO 16 $true $FUENTE_UI))
  if ($edad) { [void]$de.Children.Add((Texto "act. $edad" $C_GRIS2 10)) }
  [void]$de.Children.Add((Detalle $ms ($H - 80)))
  [void]$g.Children.Add((Colocar $de 1))
  $g
}

function Vacio {
  $s = New-Object System.Windows.Controls.StackPanel; $s.VerticalAlignment = 'Center'
  [void]$s.Children.Add((Texto 'Claude · uso' $C_BLANCO 13 $false $FUENTE_UI))
  [void]$s.Children.Add((Texto 'Sin datos: abrí Claude Code y mandá un mensaje.' $C_GRIS2 10))
  $s
}

function Medidas {
  $w = $ventana.ActualWidth; $h = $ventana.ActualHeight
  if ($w -le 0) { $w = $ventana.Width; $h = $ventana.Height }
  $w, $h
}
function Modo($w, $h) {
  if ($h -lt 95) { 'tira' } elseif ($h -lt 190) { 'media' } elseif ($w -gt $h * 1.35) { 'altoancho' } else { 'alto' }
}

$script:ultimo = ''
function Actualizar([bool]$forzar = $false) {
  $W, $H = Medidas
  $modo = Modo $W $H
  $datos = if (Test-Path $archivo) { Get-Content $archivo -Raw -Encoding UTF8 } else { '' }
  $m = $null; $min = $null
  if ($datos) { try { $m = $datos | ConvertFrom-Json; $min = [Math]::Floor(((Get-Date) - [DateTime]::Parse($m.updatedAt).ToLocalTime()).TotalMinutes) } catch {} }
  $firma = "$modo|$datos|$min|$([Math]::Round($W / 8))|$([Math]::Round($H / 8))"
  if (-not $forzar -and $firma -eq $script:ultimo) { return }
  $script:ultimo = $firma
  $raiz.Children.Clear(); $linea.Children.Clear()
  $edad = if ($null -eq $min) { $null } elseif ($min -lt 1) { 'ahora' } elseif ($min -lt 60) { "hace $min min" } else { "hace $([Math]::Floor($min / 60)) h" }
  if (-not $m) { [void]$raiz.Children.Add((Vacio)); return }
  $ms = @(Metricas $m)
  if ($ms.Count -eq 0) { [void]$raiz.Children.Add((Vacio)); return }
  switch ($modo) {
    'tira' { [void]$raiz.Children.Add((Tira $ms $edad $W $true)) }
    'media' {
      $s = New-Object System.Windows.Controls.StackPanel
      $s.Margin = '0,12,0,0'
      [void]$s.Children.Add((Tira $ms $edad $W $false))
      [void]$s.Children.Add((FilaBarras $ms $W))
      [void]$raiz.Children.Add($s)
    }
    'alto' { [void]$raiz.Children.Add((Alto $ms $edad $W $H)) }
    'altoancho' { [void]$raiz.Children.Add((AltoAncho $ms $edad $W $H)) }
  }
  # línea de progreso abajo (límite principal), como la de la canción
  $l = Barra $ms[0].pct (ColorDe $ms[0].pct) 2
  $l.Children[0].Background = Pincel '#00000000'
  [void]$linea.Children.Add($l)
  # barra superior al pasar el mouse (arrastrar / minimizar / cerrar), salvo en la tira
  $chrome.Children.Clear()
  if ($modo -ne 'tira') {
    $dots = Texto '⠿' $C_GRIS 12; $dots.HorizontalAlignment = 'Center'; $dots.ToolTip = 'Arrastrar'
    [void]$chrome.Children.Add($dots)
    $b = Botones; $b.HorizontalAlignment = 'Right'
    [void]$chrome.Children.Add($b)
  }
}

$ventana.Add_MouseEnter({
  $marco.BorderBrush = Pincel $C_VERDE; $grip.Visibility = 'Visible'
  if ($chrome.Children.Count) { $chrome.Visibility = 'Visible' } })
$ventana.Add_MouseLeave({ $marco.BorderBrush = Pincel '#2A2A2E'; $chrome.Visibility = 'Collapsed'; $grip.Visibility = 'Collapsed' })
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
