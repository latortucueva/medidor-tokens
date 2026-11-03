# Abre el medidor cada vez que se abre la app de escritorio de Claude.
# Corre oculto desde el inicio de Windows (instalar-inicio.cmd crea el acceso directo).
$widget = Join-Path $PSScriptRoot 'medidor-widget.ps1'
$antes = $false
while ($true) {
  $app = @(Get-Process -Name claude -ErrorAction SilentlyContinue | Where-Object { $_.Path -like '*\WindowsApps\Claude_*' }).Count -gt 0
  if ($app -and -not $antes) {
    # el widget tiene su propio candado: si ya está abierto, el nuevo se cierra solo
    Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-STA', '-File', "`"$widget`""
  }
  $antes = $app
  Start-Sleep -Seconds 5
}
