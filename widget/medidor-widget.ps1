# Medidor de tokens - widget flotante de escritorio (La Tortucueva)
# Lee %USERPROFILE%\.claude\medidor-tokens.json, que escribe el plugin medidor-tokens de Claude Code.
# Diseño adaptable inspirado en el mini reproductor de Spotify:
#   bajo        -> tira (logo, título y más datos a medida que se ensancha)
#   medio       -> tira + fila de barras
#   alto        -> indicador circular grande + detalle de cada límite
# OJO: en PowerShell las variables no distinguen mayúsculas; no reutilizar nombres de constantes.
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
# una sola instancia: si ya hay un medidor abierto, no abrir otro
$script:unico = New-Object System.Threading.Mutex($false, 'Local\LaTortucueva.MedidorClaude')
if (-not $script:unico.WaitOne(0)) { exit }
# ID propio en la barra de tareas: así no se agrupa con PowerShell y muestra el ícono del widget
try {
  Add-Type -Namespace Tortu -Name Shell -MemberDefinition '[DllImport("shell32.dll")] public static extern int SetCurrentProcessExplicitAppUserModelID([MarshalAs(UnmanagedType.LPWStr)] string id);'
  [void][Tortu.Shell]::SetCurrentProcessExplicitAppUserModelID('LaTortucueva.MedidorClaude')
} catch {}

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
      <Grid x:Name="Raiz" Margin="7,6,7,6" ClipToBounds="True"/>
      <Grid x:Name="Linea" Height="2" VerticalAlignment="Bottom" Margin="10,0,10,1"/>
      <Grid x:Name="Chrome" VerticalAlignment="Top" Height="20" Margin="8,3,8,0" Visibility="Collapsed"/>
      <Ellipse x:Name="Punto" Width="6" Height="6" HorizontalAlignment="Left" VerticalAlignment="Top" Margin="4,4,0,0" Fill="#3F3F46" Panel.ZIndex="5"/>
      <TextBlock x:Name="Grip" Text="◢" Foreground="#3F3F46" FontSize="9" HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,0,3,2" Visibility="Collapsed" IsHitTestVisible="False"/>
    </Grid>
  </Border>
</Window>
'@

$ventana = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$raiz = $ventana.FindName('Raiz'); $marco = $ventana.FindName('Marco')
$linea = $ventana.FindName('Linea'); $chrome = $ventana.FindName('Chrome'); $grip = $ventana.FindName('Grip')
$area = [System.Windows.SystemParameters]::WorkArea
$punto = $ventana.FindName('Punto')
$icoFile = Join-Path $PSScriptRoot 'medidor.ico'
$icoSrc = if (Test-Path $icoFile) { $icoFile } else { $logo }
if (Test-Path $icoSrc) { try { $ventana.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create([Uri]$icoSrc) } catch {} }
$ventana.Left = $area.Right - 316; $ventana.Top = $area.Bottom - 74

$conv = New-Object System.Windows.Media.BrushConverter
function Pincel($hex) { $conv.ConvertFromString($hex) }
$FUENTE_MONO = 'JetBrains Mono, Consolas'; $FUENTE_UI = 'Segoe UI Semibold, Segoe UI'
$C_VERDE = '#00FF66'; $C_NARANJA = '#FF4500'; $C_BLANCO = '#FAFAFA'; $C_GRIS = '#71717A'; $C_GRIS2 = '#A1A1AA'; $C_PISTA = '#27272A'; $C_TARJ = '#121815'

$script:k = 1.0   # escala de texto/barras en las vistas altas
function Texto($txt, $color, $tam, $negrita = $false, $fuente = $FUENTE_MONO) {
  $t = New-Object System.Windows.Controls.TextBlock
  $t.Text = $txt; $t.Foreground = Pincel $color; $t.FontFamily = $fuente; $t.FontSize = $tam * $script:k
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
  $kk = $script:k; $script:k = 1.0
  $centro = New-Object System.Windows.Controls.StackPanel
  $centro.HorizontalAlignment = 'Center'; $centro.VerticalAlignment = 'Center'
  $n = Texto "$([Math]::Round([double]$pct))%" $C_BLANCO ([Math]::Max(14, $tam * 0.2)) $true; $n.HorizontalAlignment = 'Center'
  [void]$centro.Children.Add($n)
  $e = Texto $etiqueta $C_GRIS2 ([Math]::Max(9, $tam * 0.065)); $e.HorizontalAlignment = 'Center'
  [void]$centro.Children.Add($e)
  [void]$cv.Children.Add($centro)
  $script:k = $kk
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
  $th.Width = $tam; $th.Height = $tam
  if ($script:iconoBmp) {   # mismo ícono dinámico de la barra de tareas
    $img = New-Object System.Windows.Controls.Image; $img.Source = $script:iconoBmp
    [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($img, 'HighQuality'); $th.Child = $img
  } elseif (Test-Path $logo) {
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
$script:viejo = $false
# degradé progresivo: verde azulado -> verde -> verde amarillento -> amarillo -> naranja -> rojo
$GRADIENTE = @(@(0, 0x00, 0xE5, 0xC8), @(25, 0x00, 0xFF, 0x66), @(45, 0x9B, 0xFF, 0x1F), @(60, 0xFF, 0xE6, 0x00), @(78, 0xFF, 0x8A, 0x00), @(100, 0xFF, 0x2A, 0x1F))
function FechaDe($iso) { if (-not $iso) { return $null }; try { [DateTime]::Parse($iso).ToLocalTime() } catch { $null } }
# tiempo que falta para que se renueve: corto '2h15m' / largo '2 h 15 min'
function Falta($fin, [bool]$corto = $false) {
  if (-not $fin) { return $null }
  $t = $fin - (Get-Date); if ($t.TotalSeconds -le 0) { return $(if ($corto) { 'ya' } else { 'ahora' }) }
  $d = [int][Math]::Floor($t.TotalDays); $h = $t.Hours; $m = $t.Minutes
  if ($corto) { if ($d -gt 0) { "${d}d${h}h" } elseif ($h -gt 0) { "${h}h$('{0:D2}' -f $m)m" } else { "${m}m" } }
  else { if ($d -gt 0) { "$d d $h h" } elseif ($h -gt 0) { "$h h $m min" } else { "$m min" } }
}
function ColorDe($p) {
  if ($script:viejo) { return $C_GRIS }
  $v = [Math]::Max(0.0, [Math]::Min(100.0, [Math]::Round([double]$p)))
  for ($i = 1; $i -lt $GRADIENTE.Count; $i++) {
    $b = $GRADIENTE[$i]
    if ($v -le $b[0]) {
      $a = $GRADIENTE[$i - 1]; $t = ($v - $a[0]) / ($b[0] - $a[0])
      return '#{0:X2}{1:X2}{2:X2}' -f [int]($a[1] + ($b[1] - $a[1]) * $t), [int]($a[2] + ($b[2] - $a[2]) * $t), [int]($a[3] + ($b[3] - $a[3]) * $t)
    }
  }
  '#FF2A1F'
}

# ---------- uso en vivo desde Anthropic (endpoint interno, con autodiagnóstico) ----------
# Consulta cada 90 s. Si falla: registra el motivo, avisa una vez, reintenta con espera creciente
# y mientras tanto usa el archivo del plugin. Cuando vuelve a andar, se recupera solo.
Add-Type -AssemblyName System.Net.Http, System.Windows.Forms, System.Drawing
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
$http = New-Object System.Net.Http.HttpClient; $http.Timeout = [TimeSpan]::FromSeconds(40)
$credFile = Join-Path $env:USERPROFILE '.claude\.credentials.json'
$logFile = Join-Path $env:USERPROFILE '.claude\medidor-salud.log'
$URL_USO = 'https://api.anthropic.com/api/oauth/usage'
$script:api = $null; $script:apiEstado = 'iniciando'; $script:apiMotivo = 'conectando…'
$script:tarea = $null; $script:proxima = Get-Date; $script:fallos = 0; $script:avisado = ''
$aviso = New-Object System.Windows.Forms.NotifyIcon
$aviso.Icon = if (Test-Path (Join-Path $PSScriptRoot 'medidor.ico')) { New-Object System.Drawing.Icon (Join-Path $PSScriptRoot 'medidor.ico') } else { [System.Drawing.SystemIcons]::Information }; $aviso.Text = 'Medidor Claude'
function Log($t) { try { Add-Content -Path $logFile -Value "$(Get-Date -Format s) $t" -Encoding UTF8 } catch {} }
function Avisar($t) {
  if ($script:avisado -eq $t) { return }; $script:avisado = $t
  try { $aviso.Visible = $true; $aviso.ShowBalloonTip(8000, 'Medidor Claude', $t, 'Warning') } catch {}
}
function LeerUso($body) {
  try { $j = $body | ConvertFrom-Json } catch { return $null }
  $out = @()
  foreach ($p in @(@('five_hour', '5 h', 'Límite 5 h'), @('seven_day', 'Sem', 'Semana'))) {
    $o = $j.($p[0])
    if ($o -and $null -ne $o.utilization) { $out += [pscustomobject]@{ n = $p[1]; largo = $p[2]; pct = [double]$o.utilization; ren = (Renueva $o.resets_at); fin = (FechaDe $o.resets_at) } }
  }
  if ($out.Count -eq 0 -and $j.limits) {   # plan B: formato nuevo con lista de límites
    foreach ($l in $j.limits) {
      if ($null -eq $l.percent) { continue }
      $n = if ($l.group -eq 'session') { '5 h' } elseif ($l.group -eq 'weekly') { 'Sem' } else { "$($l.kind)" }
      $lg = if ($n -eq '5 h') { 'Límite 5 h' } elseif ($n -eq 'Sem') { 'Semana' } else { "$($l.kind)" }
      $out += [pscustomobject]@{ n = $n; largo = $lg; pct = [double]$l.percent; ren = (Renueva $l.resets_at); fin = (FechaDe $l.resets_at) }
    }
  }
  if ($out.Count) { , $out } else { $null }
}
function MarcarFallo($m) {
  $script:fallos++
  if ($script:apiMotivo -ne $m) { Log "FALLO: $m" }
  $script:apiEstado = 'falla'; $script:apiMotivo = $m
  $esp = if ($script:fallos -le 2) { 20 } else { [Math]::Min(900, 90 * [Math]::Pow(2, [Math]::Min($script:fallos - 3, 3))) }
  $script:proxima = (Get-Date).AddSeconds($esp)
  if ($script:fallos -ge 3) { Avisar "No puedo leer el uso en vivo: $m. Sigo con el dato de Claude Code y reintento solo." }
}
function PedirApi {
  if ($script:tarea -or (Get-Date) -lt $script:proxima) { return }
  $tok = $null
  try { $tok = (Get-Content $credFile -Raw | ConvertFrom-Json).claudeAiOauth.accessToken } catch {}
  if (-not $tok) { MarcarFallo 'no encuentro la sesión de Claude Code en esta PC'; return }
  try {
    $req = New-Object System.Net.Http.HttpRequestMessage ([System.Net.Http.HttpMethod]::Get), $URL_USO
    [void]$req.Headers.TryAddWithoutValidation('Authorization', "Bearer $tok")
    [void]$req.Headers.TryAddWithoutValidation('anthropic-beta', 'oauth-2025-04-20')
    $script:tarea = $http.SendAsync($req)
  } catch { MarcarFallo 'no pude armar la consulta' }
}
function RevisarApi {
  $t = $script:tarea
  if (-not $t -or -not $t.IsCompleted) { return }
  $script:tarea = $null
  if ($t.IsFaulted -or $t.IsCanceled) { $ex = if ($t.Exception) { $t.Exception.GetBaseException().Message } else { 'tiempo agotado' }; MarcarFallo "sin conexión con api.anthropic.com ($ex)"; return }
  $r = $t.Result; $cod = [int]$r.StatusCode
  if ($cod -eq 401 -or $cod -eq 403) { MarcarFallo 'sesión vencida: abrí Claude Code y se renueva sola'; return }
  if ($cod -eq 404 -or $cod -eq 410) { MarcarFallo "Anthropic cerró o movió el endpoint ($cod)"; return }
  if ($cod -ne 200) { MarcarFallo "el endpoint respondió $cod"; return }
  $ms = LeerUso ($r.Content.ReadAsStringAsync().Result)
  if (-not $ms) { MarcarFallo 'cambió el formato de la respuesta'; return }
  if ($script:apiEstado -eq 'falla') { Log 'RECUPERADO: el endpoint volvió a funcionar'; if ($script:avisado) { Avisar 'El uso en vivo volvió a funcionar.' } }
  elseif ($script:apiEstado -eq 'iniciando') { Log 'OK: uso en vivo funcionando' }
  $nuevo5 = @($ms | Where-Object { $_.n -eq '5 h' })[0]
  $antes = if ($script:api) { @($script:api.ms | Where-Object { $_.n -eq '5 h' })[0] } else { $null }
  if ($antes -and $antes.pct -ge 10) {
    $ahora = if ($nuevo5) { $nuevo5.pct } else { 0 }
    if ($antes.pct - $ahora -ge 15) { Renovado $antes.pct $ahora }
  }
  $script:api = [pscustomobject]@{ ms = $ms; t = Get-Date }
  $script:apiEstado = 'ok'; $script:apiMotivo = 'en vivo desde Anthropic (cada 90 s)'; $script:fallos = 0; $script:avisado = ''
  $script:proxima = (Get-Date).AddSeconds(90)
}

function Metricas($m) {
  $out = @()
  foreach ($l in $m.limits) {
    $n = switch ($l.kind) { 'five_hour' { '5 h' } 'seven_day' { 'Sem' } default { $l.kind } }
    $largo = switch ($l.kind) { 'five_hour' { 'Límite 5 h' } 'seven_day' { 'Semana' } default { $l.kind } }
    $out += [pscustomobject]@{ n = $n; largo = $largo; pct = [double]$l.percentUsed; ren = (Renueva $l.resetsAt); fin = (FechaDe $l.resetsAt) }
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
function Tira($ms, $edad, $W, $conBotones, $conMetricas = $true) {
  $g = New-Object System.Windows.Controls.Grid
  $g.Height = 40
  Cols $g @(40, '*', 'a', 'a')
  [void]$g.Children.Add((Miniatura 38))
  $info = New-Object System.Windows.Controls.StackPanel
  $info.VerticalAlignment = 'Center'; $info.Margin = '7,0,4,0'
  [void]$info.Children.Add((Texto 'Claude · uso' $C_BLANCO 13 $false $FUENTE_UI))
  if ($edad) { [void]$info.Children.Add((Texto "act. $edad" $C_GRIS2 10)) }
  if ($W -ge 230) { [void]$g.Children.Add((Colocar $info 1)) }
  $libre = $W - 14 - 40 - 115 - $(if ($conBotones) { 50 } else { 0 })
  $detalle = $libre -ge 420
  $ancho = if ($detalle) { 140 } else { 104 }
  $cuantas = [Math]::Max(1, [Math]::Min($ms.Count, [Math]::Floor($libre / $ancho)))
  $sp = New-Object System.Windows.Controls.StackPanel
  $sp.Orientation = 'Horizontal'; $sp.VerticalAlignment = 'Center'
  foreach ($x in $ms[0..($cuantas - 1)]) {
    $col = ColorDe $x.pct
    $mm = New-Object System.Windows.Controls.StackPanel
    $mm.Margin = '8,0,2,0'; $mm.VerticalAlignment = 'Center'
    $f = New-Object System.Windows.Controls.StackPanel; $f.Orientation = 'Horizontal'
    [void]$f.Children.Add((Texto "$($x.n) " $C_GRIS2 10.5))
    [void]$f.Children.Add((Texto "$([Math]::Round($x.pct))%" $col 12 $true))
    $fc = Falta $x.fin $true
    if ($fc -and -not $detalle) { $tf = Texto " $fc" $C_GRIS 10; $tf.VerticalAlignment = 'Bottom'; $tf.ToolTip = "se renueva en $(Falta $x.fin)"; [void]$f.Children.Add($tf) }
    [void]$mm.Children.Add($f)
    if ($detalle) {
      $b = Barra $x.pct $col 3; $b.Width = 120; $b.Margin = '0,3,0,2'; [void]$mm.Children.Add($b)
      $fl = Falta $x.fin
      $txt = if ($fl) { "se renueva en $fl" } else { $x.ren }
      if ($txt) { [void]$mm.Children.Add((Texto $txt $C_GRIS 9)) }
    }
    [void]$sp.Children.Add($mm)
  }
  if ($conMetricas) { [void]$g.Children.Add((Colocar $sp 2)) }
  if ($conBotones) { $bt = Botones; $bt.Margin = '6,0,0,0'; [void]$g.Children.Add((Colocar $bt 3)) }
  $g
}

# ---------- fila de barras (altura media) ----------
function FilaBarras($ms, $W) {
  $g = New-Object System.Windows.Controls.Grid
  $g.Margin = '0,6,0,0'
  $cuantas = [Math]::Max(1, [Math]::Min($ms.Count, [Math]::Floor(($W - 14) / 80)))
  Cols $g (@('*') * $cuantas)
  $i = 0
  foreach ($x in $ms[0..($cuantas - 1)]) {
    $col = ColorDe $x.pct
    $s = New-Object System.Windows.Controls.StackPanel
    $s.Margin = $(if ($i -eq 0) { '0,0,6,0' } else { '6,0,6,0' })
    $h = New-Object System.Windows.Controls.Grid; Cols $h @('*', 'a')
    $fc = Falta $x.fin $true
    [void]$h.Children.Add((Texto $(if ($fc) { "$($x.n) · $fc" } else { $x.n }) $C_GRIS2 10))
    [void]$h.Children.Add((Colocar (Texto "$([Math]::Round($x.pct))%" $col 11 $true) 1))
    [void]$s.Children.Add($h)
    $b = Barra $x.pct $col 4; $b.Margin = '0,4,0,0'; [void]$s.Children.Add($b)
    [void]$g.Children.Add((Colocar $s $i)); $i++
  }
  $g
}

# ---------- lista vertical (vista media angosta) ----------
function ListaMedia($ms, $W, $H) {
  $g = New-Object System.Windows.Controls.Grid
  $g.Margin = '2,2,2,4'
  $alto = $H - 12 - 6
  $cuantas = [Math]::Max(1, [Math]::Min($ms.Count, [Math]::Floor($alto / 40)))
  Filas $g (@('*') * $cuantas)
  $i = 0
  foreach ($x in $ms[0..($cuantas - 1)]) {
    $col = ColorDe $x.pct
    $s = New-Object System.Windows.Controls.StackPanel; $s.VerticalAlignment = 'Center'
    $h = New-Object System.Windows.Controls.Grid; Cols $h @('*', 'a')
    $n = Texto $x.largo $C_BLANCO 11.5 $false $FUENTE_UI; $n.VerticalAlignment = 'Bottom'
    [void]$h.Children.Add($n)
    [void]$h.Children.Add((Colocar (Texto "$([Math]::Round($x.pct))%" $col 14 $true) 1))
    [void]$s.Children.Add($h)
    $b = Barra $x.pct $col 4; $b.Margin = '0,3,0,0'; [void]$s.Children.Add($b)
    $fl = Falta $x.fin
    if ($fl) { $tf = Texto "se renueva en $fl" $C_GRIS 9.5; $tf.Margin = '0,2,0,0'; [void]$s.Children.Add($tf) }
    [void]$g.Children.Add((Colocar $s 0 $i)); $i++
  }
  $g
}

# ---------- detalle (lista, como la fila de reproducción) ----------
function Detalle($ms, $maxAlto, $conSep = $true) {
  $s = New-Object System.Windows.Controls.StackPanel
  $s.Margin = '0,5,0,0'
  $sep = New-Object System.Windows.Controls.Grid; Cols $sep @('*', 'a', '*')
  foreach ($c in 0, 2) { $l = New-Object System.Windows.Controls.Border; $l.Height = 1; $l.Background = Pincel '#2A2A2E'; [void]$sep.Children.Add((Colocar $l $c)) }
  $tt = Texto ' DETALLE ' $C_GRIS 9; [void]$sep.Children.Add((Colocar $tt 1))
  if ($conSep) { [void]$s.Children.Add($sep) }
  $fila = 34 * $script:k; $usado = 22 * $script:k
  foreach ($x in $ms) {
    if ($usado + $fila -gt $maxAlto) { break }
    $col = ColorDe $x.pct
    $r = New-Object System.Windows.Controls.Grid; $r.Margin = "0,$([Math]::Round(5 * $script:k)),0,0"; Cols $r @('*', 'a')
    $iz = New-Object System.Windows.Controls.StackPanel
    [void]$iz.Children.Add((Texto $x.largo $C_BLANCO 12 $false $FUENTE_UI))
    $sub = if ($x.ren) { if ($x.n -eq 'Ctx') { $x.ren } else { "se renueva $($x.ren)" } } else { '' }   # vistas grandes: hora exacta
    [void]$iz.Children.Add((Texto $sub $C_GRIS 9.5))
    [void]$r.Children.Add($iz)
    $p = Texto "$([Math]::Round($x.pct))%" $col 13 $true; $p.VerticalAlignment = 'Center'
    [void]$r.Children.Add((Colocar $p 1))
    [void]$s.Children.Add($r)
    $b = Barra $x.pct $col (3 * $script:k); $b.Margin = '0,4,0,0'; [void]$s.Children.Add($b)
    $usado += $fila
  }
  $s
}

# ---------- vista alta: anillo grande + título + detalle ----------
function Alto($ms, $edad, $W, $H) {
  $principal = $ms[0]
  $g = New-Object System.Windows.Controls.Grid
  $g.Margin = '0,10,0,6'
  $anchoUtil = $W - 14; $altoUtil = $H - 12 - 16
  $script:k = [Math]::Max(1.0, [Math]::Min(2.2, [Math]::Min($anchoUtil / 240, $altoUtil / 420)))
  $resto = @($ms | Select-Object -Skip 1)
  $conDetalle = $altoUtil -ge 300 -and $resto.Count -gt 0
  $tam = [Math]::Min($anchoUtil - 8, $altoUtil - 50 * $script:k - $(if ($conDetalle) { (22 + 34 * $resto.Count) * $script:k } else { 0 }))
  $tam = [Math]::Max(70, [Math]::Min($tam, 420))
  Filas $g @('*', 'a')
  $s = New-Object System.Windows.Controls.StackPanel
  $a = Anillo $principal.pct (ColorDe $principal.pct) $tam $principal.n; $a.HorizontalAlignment = 'Center'
  $a.VerticalAlignment = 'Center'
  [void]$g.Children.Add($a)
  $t = New-Object System.Windows.Controls.Grid; $t.Margin = '2,6,0,0'; Cols $t @('*', 'a')
  $info = New-Object System.Windows.Controls.StackPanel
  [void]$info.Children.Add((Texto $principal.largo $C_BLANCO 16 $true $FUENTE_UI))
  $sub = if ($principal.ren) { "se renueva $($principal.ren)" } else { '' }
  if ($edad) { $sub = if ($sub) { "$sub · act. $edad" } else { "act. $edad" } }
  [void]$info.Children.Add((Texto $sub $C_GRIS2 10))
  [void]$t.Children.Add($info)
  [void]$s.Children.Add($t)
  if ($conDetalle) { [void]$s.Children.Add((Detalle $resto ($altoUtil - $tam - 40 * $script:k))) }
  $s.VerticalAlignment = 'Bottom'
  [void]$g.Children.Add((Colocar $s 0 1))
  $g
}

# ---------- vista alta y ancha: anillo a la izquierda, detalle a la derecha ----------
function AltoAncho($ms, $edad, $W, $H) {
  $g = New-Object System.Windows.Controls.Grid
  $g.Margin = '0,10,0,0'
  Cols $g @('a', '*')
  $script:k = [Math]::Max(1.0, [Math]::Min(2.2, [Math]::Min(($W - 14) / 480, ($H - 22) / 230)))
  $tam = [Math]::Max(70, [Math]::Min([Math]::Min(($H - 26) * 0.88, ($W - 14) * 0.4), 400))
  $iz = New-Object System.Windows.Controls.StackPanel; $iz.VerticalAlignment = 'Center'
  [void]$iz.Children.Add((Anillo $ms[0].pct (ColorDe $ms[0].pct) $tam $ms[0].n))
  [void]$g.Children.Add($iz)
  $de = New-Object System.Windows.Controls.StackPanel; $de.Margin = "$([Math]::Round(14 * $script:k)),0,0,0"; $de.VerticalAlignment = 'Center'
  [void]$de.Children.Add((Texto 'Claude · uso' $C_BLANCO 16 $true $FUENTE_UI))
  if ($edad) { [void]$de.Children.Add((Texto "act. $edad" $C_GRIS2 10)) }
  [void]$de.Children.Add((Detalle $ms ($H - 22 - 40 * $script:k) $false))
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
  $w = $ventana.Width; $h = $ventana.Height
  if ([double]::IsNaN($w) -or $w -le 0) { $w = $ventana.ActualWidth; $h = $ventana.ActualHeight }
  $w, $h
}
function Modo($w, $h) {
  if ($h -lt 95) { 'tira' } elseif ($h -lt 190) { if ($w -lt 300) { 'lista' } else { 'media' } } elseif ($w -gt $h * 1.35) { 'altoancho' } else { 'alto' }
}

# ---------- ícono dinámico: el anillo del ícono sigue al límite principal ----------
$script:iconoFirma = ''; $script:iconoBmp = $null
$script:logoBmp = $null
if (Test-Path $logo) { try { $script:logoBmp = New-Object System.Windows.Media.Imaging.BitmapImage; $script:logoBmp.BeginInit(); $script:logoBmp.UriSource = [Uri]$logo; $script:logoBmp.DecodePixelWidth = 128; $script:logoBmp.CacheOption = 'OnLoad'; $script:logoBmp.EndInit() } catch { $script:logoBmp = $null } }
$script:logosTenidos = @{}
function LogoTenido($color) {
  if (-not $script:logoBmp) { return $null }
  if ($script:logosTenidos.ContainsKey($color)) { return $script:logosTenidos[$color] }
  try {
    $src = New-Object System.Windows.Media.Imaging.FormatConvertedBitmap $script:logoBmp, ([System.Windows.Media.PixelFormats]::Bgra32), $null, 0
    $w = $src.PixelWidth; $h = $src.PixelHeight; $paso = $w * 4
    $px = New-Object byte[] ($paso * $h); $src.CopyPixels($px, $paso, 0)
    $c = [System.Windows.Media.ColorConverter]::ConvertFromString($color)
    $cx = $w / 2.0; $cy = $h / 2.0; $lim = 0.70 * $w / 2.0
    for ($i = 0; $i -lt $px.Length; $i += 4) {
      $q = $i / 4; $dx = ($q % $w) - $cx; $dy = [Math]::Floor($q / $w) - $cy
      if ($dx * $dx + $dy * $dy -gt $lim * $lim) { $px[$i] = 0; $px[$i + 1] = 0; $px[$i + 2] = 0; $px[$i + 3] = 0; continue }   # quita el aro del logo
      $l = [Math]::Max($px[$i], [Math]::Max($px[$i + 1], $px[$i + 2])) / 255.0
      # sin el disco oscuro: lo claro queda opaco y brillante, lo oscuro transparente
      $a = [Math]::Min(1.0, [Math]::Max(0.0, ($l - 0.18) * 2.2)) * ($px[$i + 3] / 255.0)
      $px[$i] = [byte]($c.B * $a); $px[$i + 1] = [byte]($c.G * $a); $px[$i + 2] = [byte]($c.R * $a); $px[$i + 3] = [byte](255 * $a)
    }
    $bmp = [System.Windows.Media.Imaging.BitmapSource]::Create($w, $h, 96, 96, ([System.Windows.Media.PixelFormats]::Bgra32), $null, $px, $paso)
    $bmp.Freeze(); $script:logosTenidos[$color] = $bmp; $bmp
  } catch { $script:logoBmp }
}
function IconoDinamico($pct, $color) {
  $firma = "$([Math]::Round($pct))|$color"
  if ($firma -eq $script:iconoFirma) { return }
  $script:iconoFirma = $firma
  try {
    $S = 64.0; $w = 5.5; $r = ($S - 2 * 3 - $w) / 2; $c = $S / 2
    $dv = New-Object System.Windows.Media.DrawingVisual
    $dc = $dv.RenderOpen()
    $dc.DrawEllipse((Pincel '#09090B'), $null, (New-Object System.Windows.Point $c, $c), ($r + $w / 2), ($r + $w / 2))   # silueta circular, sin cuadrado
    $pista = New-Object System.Windows.Media.Pen (Pincel $C_PISTA), $w
    $dc.DrawEllipse($null, $pista, (New-Object System.Windows.Point $c, $c), $r, $r)
    $v = [Math]::Max(0.0, [Math]::Min(99.9, [double]$pct))
    if ($v -gt 0) {
      $ang = $v / 100 * 2 * [Math]::PI
      $g = New-Object System.Windows.Media.StreamGeometry
      $ctx = $g.Open()
      $ctx.BeginFigure((New-Object System.Windows.Point $c, ($c - $r)), $false, $false)
      $ctx.ArcTo((New-Object System.Windows.Point ($c + $r * [Math]::Sin($ang)), ($c - $r * [Math]::Cos($ang))), (New-Object System.Windows.Size $r, $r), 0, ($v -gt 50), 'Clockwise', $true, $false)
      $ctx.Close()
      $arco = New-Object System.Windows.Media.Pen (Pincel $color), $w
      $arco.StartLineCap = 'Round'; $arco.EndLineCap = 'Round'
      $dc.DrawGeometry($null, $arco, $g)
    }
    $tort = LogoTenido $color
    if ($tort) { $L = 66.0; $dc.DrawImage($tort, (New-Object System.Windows.Rect (($S - $L) / 2), (($S - $L) / 2), $L, $L)) }
    $dc.Close()
    $rb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap 192, 192, 288, 288, ([System.Windows.Media.PixelFormats]::Pbgra32)
    $rb.Render($dv); $rb.Freeze(); $script:iconoBmp = $rb
    $ventana.Icon = $rb
    $ventana.Title = "Claude $([Math]::Round($pct))%"
  } catch {}
}

# ---------- renovación del límite de 5 h: sonido + aviso + anillo que retrocede ----------
$script:animPct = $null
$animTimer = New-Object System.Windows.Threading.DispatcherTimer
$animTimer.Interval = [TimeSpan]::FromMilliseconds(45)
$animTimer.Add_Tick({
  $a = $script:anim
  $t = [Math]::Min(1.0, ((Get-Date) - $a.t0).TotalMilliseconds / $a.dur)
  $e = 1 - [Math]::Pow(1 - $t, 3)   # frena al final
  $script:animPct = $a.desde + ($a.hasta - $a.desde) * $e
  Actualizar $true
  if ($t -ge 1) { $animTimer.Stop(); $script:animPct = $null; $script:iconoFirma = ''; Actualizar $true }
})
function SonidoRenovacion {
  foreach ($w in 'Windows Notify System Generic.wav', 'Windows Unlock.wav', 'tada.wav') {
    $f = Join-Path $env:WINDIR "Media\$w"
    if (Test-Path $f) { try { (New-Object System.Media.SoundPlayer $f).Play(); return } catch {} }
  }
  [System.Media.SystemSounds]::Asterisk.Play()
}
function Renovado($desde, $hasta) {
  Log "RENOVADO: límite de 5 h de $([Math]::Round($desde))% a $([Math]::Round($hasta))%"
  SonidoRenovacion
  try { $aviso.Visible = $true; $aviso.ShowBalloonTip(8000, 'Límite de 5 h renovado 🐢', "Ya podés volver a usar Claude. Uso actual: $([Math]::Round($hasta))%.", 'Info') } catch {}
  if ($ventana.WindowState -eq 'Minimized') { $ventana.WindowState = 'Normal' }
  $script:anim = @{ desde = [double]$desde; hasta = [double]$hasta; t0 = Get-Date; dur = 1800.0 }
  $animTimer.Start()
}

$script:ultimo = ''
function Actualizar([bool]$forzar = $false) {
  RevisarApi; PedirApi
  $W, $H = Medidas
  $modo = Modo $W $H
  $datos = if (Test-Path $archivo) { Get-Content $archivo -Raw -Encoding UTF8 } else { '' }
  $m = $null; $min = $null
  if ($datos) { try { $m = $datos | ConvertFrom-Json; $min = [Math]::Floor(((Get-Date) - [DateTime]::Parse($m.updatedAt).ToLocalTime()).TotalMinutes) } catch {} }
  $vivo = $script:api -and ((Get-Date) - $script:api.t).TotalMinutes -lt 5
  if ($vivo) { $min = [Math]::Floor(((Get-Date) - $script:api.t).TotalMinutes) }
  $firma = "$((Get-Date).ToString('HHmm'))|$modo|$datos|$min|$vivo|$($script:api.t)|$($script:apiEstado)|$([Math]::Round($W / 8))|$([Math]::Round($H / 8))"
  if (-not $forzar -and $firma -eq $script:ultimo) { return }
  $script:ultimo = $firma
  $raiz.Children.Clear(); $linea.Children.Clear(); $script:k = 1.0
  $edad = if ($null -eq $min) { $null } elseif ($min -lt 1) { 'ahora' } elseif ($min -lt 60) { "hace $min min" } else { "hace $([Math]::Floor($min / 60)) h" }
  $script:viejo = (-not $vivo) -and ($null -ne $min) -and ($min -ge 10)
  if ($script:viejo) { $edad = "$edad · dato viejo" }
  $punto.Fill = Pincel $(if ($vivo) { $C_VERDE } elseif ($script:viejo) { $C_NARANJA } else { '#EAB308' })
  $punto.ToolTip = if ($vivo) { $script:apiMotivo } else { "Usando el dato de Claude Code. Uso en vivo: $($script:apiMotivo)" }
  if (-not $m -and -not $vivo) { [void]$raiz.Children.Add((Vacio)); return }
  $ms = if ($vivo) { @($script:api.ms) + @(@(if ($m) { Metricas $m }) | Where-Object { $_.n -eq 'Ctx' }) } else { @(Metricas $m) }
  if ($ms.Count -eq 0) { [void]$raiz.Children.Add((Vacio)); return }
  if ($null -ne $script:animPct) {
    $ms = @($ms | ForEach-Object { if ($_.n -eq '5 h') { $c = $_.PSObject.Copy(); $c.pct = $script:animPct; $c } else { $_ } })
    $script:viejo = $false
  }
  IconoDinamico $ms[0].pct (ColorDe $ms[0].pct)
  switch ($modo) {
    'tira' { [void]$raiz.Children.Add((Tira $ms $edad $W $true)) }
    'media' {
      $s = New-Object System.Windows.Controls.StackPanel
      $s.VerticalAlignment = 'Top'
      [void]$s.Children.Add((Tira $ms $edad $W $true $false))
      [void]$s.Children.Add((FilaBarras $ms $W))
      [void]$raiz.Children.Add($s)
    }
    'lista' { [void]$raiz.Children.Add((ListaMedia $ms $W $H)) }
    'alto' { [void]$raiz.Children.Add((Alto $ms $edad $W $H)) }
    'altoancho' { [void]$raiz.Children.Add((AltoAncho $ms $edad $W $H)) }
  }
  # línea de progreso abajo (límite principal), como la de la canción
  $script:k = 1.0
  $l = Barra $ms[0].pct (ColorDe $ms[0].pct) 2
  $l.Children[0].Background = Pincel '#00000000'
  [void]$linea.Children.Add($l)
  # barra superior al pasar el mouse (arrastrar / minimizar / cerrar), salvo en la tira
  $chrome.Children.Clear()
  if ($modo -notin @('tira', 'media')) {
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
$menu = New-Object System.Windows.Controls.ContextMenu
$itemProbar = New-Object System.Windows.Controls.MenuItem; $itemProbar.Header = 'Probar aviso de renovación'
$itemProbar.Add_Click({ $p = if ($script:api) { @($script:api.ms)[0].pct } else { 90 }; Renovado ([Math]::Max(60, $p)) 0 })
[void]$menu.Items.Add($itemProbar); $ventana.ContextMenu = $menu
$ventana.Add_Closed({ try { $aviso.Dispose() } catch {} })
$ventana.Add_StateChanged({ if ($ventana.WindowState -eq 'Normal') { $ventana.Topmost = $true } })
$ventana.Add_SizeChanged({ Actualizar })

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(3)
$timer.Add_Tick({ Actualizar })
$timer.Start()
$ventana.Add_ContentRendered({ Actualizar $true })
[void]$ventana.ShowDialog()
