# Medidor de tokens - widget flotante de escritorio (La Tortucueva)
# Lee %USERPROFILE%\.claude\medidor-tokens.json, que escribe el plugin medidor-tokens de Claude Code.
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$archivo = Join-Path $env:USERPROFILE '.claude\medidor-tokens.json'

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:shell="clr-namespace:System.Windows.Shell;assembly=PresentationFramework"
        Title="Medidor Claude" Width="300" Height="125" MinWidth="220" MinHeight="90"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="True" ResizeMode="CanResize">
  <shell:WindowChrome.WindowChrome>
    <shell:WindowChrome ResizeBorderThickness="7" CaptionHeight="0" CornerRadius="10" GlassFrameThickness="0" UseAeroCaptionButtons="False"/>
  </shell:WindowChrome.WindowChrome>
  <Border CornerRadius="10" Background="#F209090B" Margin="0" BorderBrush="#00FF66" BorderThickness="1" Padding="12,9,12,10">
    <StackPanel>
      <Grid Margin="0,0,0,6">
        <TextBlock Text="CLAUDE · USO" Foreground="#00FF66" FontFamily="JetBrains Mono, Consolas" FontSize="11" FontWeight="Bold"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
          <TextBlock x:Name="Edad" Foreground="#71717A" FontFamily="JetBrains Mono, Consolas" FontSize="10" Margin="0,1,10,0"/>
          <TextBlock x:Name="Minimizar" Text="–" Foreground="#A1A1AA" FontSize="13" Margin="0,-3,10,0" Cursor="Hand" ToolTip="Minimizar"/>
          <TextBlock x:Name="Cerrar" Text="✕" Foreground="#A1A1AA" FontSize="11" Cursor="Hand" ToolTip="Cerrar"/>
        </StackPanel>
      </Grid>
      <StackPanel x:Name="Filas"/>
    </StackPanel>
  </Border>
</Window>
'@

$ventana = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$filas = $ventana.FindName('Filas')
$edad = $ventana.FindName('Edad')
$ventana.FindName('Cerrar').Add_MouseLeftButtonUp({ $ventana.Close() })
$ventana.FindName('Minimizar').Add_MouseLeftButtonUp({ $ventana.WindowState = 'Minimized' })
$ventana.Add_MouseLeftButtonDown({ param($s, $e) if ($e.OriginalSource.Text -notin @('✕', '–') -and $e.ButtonState -eq 'Pressed') { try { $ventana.DragMove() } catch {} } })
# al volver desde la barra de tareas, seguir arriba de todo
$ventana.Add_StateChanged({ if ($ventana.WindowState -eq 'Normal') { $ventana.Topmost = $true } })

# posicion inicial: abajo a la derecha, sobre la barra de tareas
$area = [System.Windows.SystemParameters]::WorkArea
$ventana.Left = $area.Right - 316
$ventana.Top = $area.Bottom - 160

$conv = New-Object System.Windows.Media.BrushConverter
function Pincel($hex) { $conv.ConvertFromString($hex) }

function Fila($nombre, $pct, $detalle) {
  $color = if ($pct -ge 80) { '#FF4500' } else { '#00FF66' }
  $g = New-Object System.Windows.Controls.Grid
  $g.Margin = '0,3,0,0'
  foreach ($w in 54, 0, 46) {
    $c = New-Object System.Windows.Controls.ColumnDefinition
    $c.Width = if ($w -eq 0) { [System.Windows.GridLength]::new(1, 'Star') } else { [System.Windows.GridLength]::new($w) }
    $g.ColumnDefinitions.Add($c)
  }
  $t = New-Object System.Windows.Controls.TextBlock
  $t.Text = $nombre; $t.Foreground = Pincel '#FAFAFA'; $t.FontFamily = 'JetBrains Mono, Consolas'; $t.FontSize = 11
  $v = [Math]::Max(0.0, [Math]::Min(100.0, [double]$pct))
  $fondo = New-Object System.Windows.Controls.Grid
  $fondo.Height = 7; $fondo.VerticalAlignment = 'Center'; $fondo.Margin = '0,0,6,0'
  [System.Windows.Controls.Grid]::SetColumn($fondo, 1)
  $pista = New-Object System.Windows.Controls.Border
  $pista.CornerRadius = 3.5; $pista.Background = Pincel '#27272A'
  [void]$fondo.Children.Add($pista)
  $relleno = New-Object System.Windows.Controls.Grid
  $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = [System.Windows.GridLength]::new([Math]::Max($v, 0.001), 'Star')
  $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = [System.Windows.GridLength]::new([Math]::Max(100 - $v, 0.001), 'Star')
  $relleno.ColumnDefinitions.Add($c1); $relleno.ColumnDefinitions.Add($c2)
  $barra = New-Object System.Windows.Controls.Border
  $barra.CornerRadius = 3.5; $barra.Background = Pincel $color
  [void]$relleno.Children.Add($barra)
  [void]$fondo.Children.Add($relleno)
  $p = New-Object System.Windows.Controls.TextBlock
  $p.Text = "$([Math]::Round($pct))%"; $p.Foreground = Pincel $color; $p.FontFamily = 'JetBrains Mono, Consolas'; $p.FontSize = 11
  $p.HorizontalAlignment = 'Right'
  [System.Windows.Controls.Grid]::SetColumn($p, 2)
  [void]$g.Children.Add($t); [void]$g.Children.Add($fondo); [void]$g.Children.Add($p)
  [void]$filas.Children.Add($g)
  if ($detalle) {
    $d = New-Object System.Windows.Controls.TextBlock
    $d.Text = $detalle; $d.Foreground = Pincel '#71717A'; $d.FontFamily = 'JetBrains Mono, Consolas'; $d.FontSize = 9.5
    $d.Margin = '54,0,0,1'
    [void]$filas.Children.Add($d)
  }
}

$dias = 'dom', 'lun', 'mar', 'mié', 'jue', 'vie', 'sáb'
function Renueva($iso) {
  if (-not $iso) { return $null }
  try { $f = [DateTime]::Parse($iso).ToLocalTime() } catch { return $null }
  $dia = if ($f.Date -eq (Get-Date).Date) { 'hoy' } else { "$($dias[[int]$f.DayOfWeek]) $($f.Day)/$($f.Month)" }
  "se renueva $dia $($f.ToString('HH:mm'))"
}

function Actualizar {
  $filas.Children.Clear()
  if (-not (Test-Path $archivo)) {
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = "Sin datos todavía.`nAbrí Claude Code y mandá un mensaje."
    $t.Foreground = Pincel '#A1A1AA'; $t.FontFamily = 'JetBrains Mono, Consolas'; $t.FontSize = 10.5
    [void]$filas.Children.Add($t); $edad.Text = ''; return
  }
  try { $m = Get-Content $archivo -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return }
  $pct = $m.percent
  if ($null -eq $pct -and $m.tokens -and $m.window) { $pct = $m.tokens / $m.window * 100 }
  if ($null -ne $pct) {
    $k = { param($n) if ($n -ge 1000) { "$([Math]::Round($n / 1000))k" } else { "$n" } }
    $det = if ($m.tokens) { "$(& $k $m.tokens) / $(& $k $m.window) tokens" } else { $null }
    Fila 'Ctx' $pct $det
  }
  foreach ($l in $m.limits) {
    $n = switch ($l.kind) { 'five_hour' { '5 h' } 'seven_day' { 'Sem' } default { $l.kind } }
    Fila $n $l.percentUsed (Renueva $l.resetsAt)
  }
  if ($m.updatedAt) {
    $min = [Math]::Floor(((Get-Date) - [DateTime]::Parse($m.updatedAt).ToLocalTime()).TotalMinutes)
    $edad.Text = if ($min -lt 1) { 'ahora' } elseif ($min -lt 60) { "hace $min min" } else { "hace $([Math]::Floor($min / 60)) h" }
  }
}

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(3)
$timer.Add_Tick({ Actualizar })
$timer.Start()
Actualizar
[void]$ventana.ShowDialog()
