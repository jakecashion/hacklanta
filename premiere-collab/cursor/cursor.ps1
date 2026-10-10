# cursor.ps1 - live cursor helper (Phase 3, PRES-04). Runs next to Premiere on each laptop.
# Sends where your mouse is inside Premiere's main window (x, y from 0 to 1) to the relay,
# and draws the other editor's pointer over your own Premiere in a transparent,
# click-through, always-on-top overlay. The CEP panel can't do this: it can't see or draw
# outside itself. Both Premieres must be maximized with the same workspace, or the pointer
# lands only roughly on the same spot.
#
#   Two laptops:  powershell -ExecutionPolicy Bypass -File cursor.ps1 -Relay 100.101.102.103 -Name Guest
#   Host laptop:  powershell -ExecutionPolicy Bypass -File cursor.ps1 -Relay localhost -Name Host
#   Probe:        powershell -ExecutionPolicy Bypass -File cursor.ps1 -Loopback
#                 (no network: draws a ring where it maps your own pointer; the ring must sit
#                 around the real pointer, and clicks must still reach Premiere through it)
#
# Messages (relay forwards unknown types to everyone else): {type:'cursor', name, x, y, inside}
param(
    [string]$Relay = 'localhost',
    [string]$Name = $env:USERNAME,
    [switch]$Loopback,
    [int]$Hz = 20
)
$ErrorActionPreference = 'Stop'

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class PcWin {
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int attr, out RECT r, int size);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
    [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h, int i, int v);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int hgt, uint flags);

    // Visible frame of a window in physical pixels (without the invisible resize border).
    public static RECT Frame(IntPtr h) {
        RECT r;
        if (DwmGetWindowAttribute(h, 9, out r, Marshal.SizeOf(typeof(RECT))) != 0) GetWindowRect(h, out r);
        return r;
    }
    public static uint Pid(IntPtr h) { uint pid; GetWindowThreadProcessId(h, out pid); return pid; }
}
"@
# Physical pixels everywhere (laptops often run at 150-175% scaling). WPF then reports its
# DIP scale through TransformToDevice, used when drawing.
[void][PcWin]::SetProcessDPIAware()
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# All mutable state lives in one hashtable: event handlers run in their own scope.
$S = @{
    Premiere = [IntPtr]::Zero; PremierePid = 0; LastFind = [DateTime]::MinValue
    Rect = $null; Scale = 1.0; OverlayHwnd = [IntPtr]::Zero
    Ws = $null; ConnectTask = $null; RecvTask = $null; SendTask = $null; NextConnect = [DateTime]::MinValue
    RecvText = ''; LastSent = ''; LastSentAt = [DateTime]::MinValue
    RemoteAt = [DateTime]::MinValue; RemoteX = 0.0; RemoteY = 0.0; RemoteInside = $false; RemoteName = ''
    Status = ''
}
$RecvBuf = New-Object byte[] 16384
$Url = if ($Relay -match '^wss?://') { $Relay } elseif ($Relay -match ':\d+$') { "ws://$Relay" } else { "ws://${Relay}:8080" }

# ---------- Windows ----------
$overlayXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent" Topmost="True"
        ShowInTaskbar="False" ShowActivated="False" ResizeMode="NoResize" Width="10" Height="10" Left="0" Top="0">
  <Canvas>
    <Canvas x:Name="Ptr" Visibility="Hidden">
      <Path Data="M0,0 L0,24 L6.5,18 L11,28 L15,26 L10.5,16.5 L19,16.5 Z" Fill="#FFE8413C" Stroke="White" StrokeThickness="1.5"/>
      <Border Canvas.Left="16" Canvas.Top="24" Background="#FFE8413C" CornerRadius="4" Padding="6,2">
        <TextBlock x:Name="Label" Foreground="White" FontSize="13" FontWeight="SemiBold" Text="Editor"/>
      </Border>
    </Canvas>
    <Ellipse x:Name="Ring" Width="34" Height="34" Stroke="#FF35C0FF" StrokeThickness="3" Visibility="Hidden"/>
  </Canvas>
</Window>
"@
$controlXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Live cursor" SizeToContent="WidthAndHeight" Topmost="True" ResizeMode="NoResize"
        WindowStartupLocation="Manual" Left="12" Top="12" Background="#FF1E1E1E">
  <StackPanel Orientation="Horizontal" Margin="8">
    <TextBlock x:Name="Status" Foreground="#FFDDDDDD" FontSize="12" VerticalAlignment="Center" MinWidth="260" Text="Starting"/>
    <Button x:Name="Quit" Content="Quit" Margin="8,0,0,0" Padding="10,2"/>
  </StackPanel>
</Window>
"@
$overlay = [Windows.Markup.XamlReader]::Parse($overlayXaml)
$control = [Windows.Markup.XamlReader]::Parse($controlXaml)
$ptr = $overlay.FindName('Ptr'); $label = $overlay.FindName('Label'); $ring = $overlay.FindName('Ring')
$statusText = $control.FindName('Status')
$control.FindName('Quit').Add_Click({ $control.Close() })

$overlay.Add_SourceInitialized({
    $h = (New-Object System.Windows.Interop.WindowInteropHelper $overlay).Handle
    $S.OverlayHwnd = $h
    # WS_EX_TRANSPARENT | WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE: clicks pass through,
    # no taskbar button, never takes focus.
    $ex = [PcWin]::GetWindowLong($h, -20)
    [void][PcWin]::SetWindowLong($h, -20, ($ex -bor 0x20 -bor 0x80000 -bor 0x80 -bor 0x08000000))
})

function Set-Status([string]$text) {
    if ($S.Status -ne $text) { $S.Status = $text; $statusText.Text = $text }
}

# ---------- Premiere window ----------
function Update-Premiere {
    if ($S.Premiere -ne [IntPtr]::Zero -and [PcWin]::IsWindow($S.Premiere)) { return }
    if (([DateTime]::Now - $S.LastFind).TotalSeconds -lt 2) { return }
    $S.LastFind = [DateTime]::Now
    $p = Get-Process -Name 'Adobe Premiere Pro' -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } | Select-Object -First 1
    if ($p) { $S.Premiere = $p.MainWindowHandle; $S.PremierePid = $p.Id }
    else { $S.Premiere = [IntPtr]::Zero; $S.PremierePid = 0 }
}

# Show the overlay only while Premiere (or this helper) is in front, so the drawn pointer
# doesn't float over other apps.
function Test-PremiereInFront {
    $fg = [PcWin]::GetForegroundWindow()
    $fgPid = [PcWin]::Pid($fg)
    return ($fgPid -eq $S.PremierePid -or $fgPid -eq $PID)
}

# Keep the overlay exactly on top of Premiere's frame (physical pixels, no activation).
function Sync-Overlay($r) {
    $old = $S.Rect
    if ($old -and $old.Left -eq $r.Left -and $old.Top -eq $r.Top -and $old.Right -eq $r.Right -and $old.Bottom -eq $r.Bottom) { return }
    $S.Rect = $r
    # HWND_TOPMOST, SWP_NOACTIVATE
    [void][PcWin]::SetWindowPos($S.OverlayHwnd, [IntPtr](-1), $r.Left, $r.Top, ($r.Right - $r.Left), ($r.Bottom - $r.Top), 0x10)
}

# Place an element at a normalized (0..1) point of Premiere's frame. Canvas units are DIPs.
function Move-ToNormalized($el, [double]$nx, [double]$ny, [double]$dx, [double]$dy) {
    $r = $S.Rect
    [Windows.Controls.Canvas]::SetLeft($el, ($nx * ($r.Right - $r.Left)) / $S.Scale + $dx)
    [Windows.Controls.Canvas]::SetTop($el, ($ny * ($r.Bottom - $r.Top)) / $S.Scale + $dy)
}

# ---------- Relay ----------
function Reset-Socket([string]$why) {
    if ($S.Ws) { try { $S.Ws.Dispose() } catch { } }
    $S.Ws = $null; $S.ConnectTask = $null; $S.RecvTask = $null; $S.SendTask = $null; $S.RecvText = ''
    $S.NextConnect = [DateTime]::Now.AddSeconds(3)
    Set-Status "Not connected ($why). Retrying $Url"
}

function Send-Json([string]$json) {
    if (-not $S.Ws -or $S.Ws.State -ne [System.Net.WebSockets.WebSocketState]::Open) { return $false }
    if ($S.SendTask -and -not $S.SendTask.IsCompleted) { return $false } # one send at a time; skip this frame
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $seg = New-Object 'System.ArraySegment[byte]' -ArgumentList (, $bytes)
    $S.SendTask = $S.Ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None)
    return $true
}

function On-Message([string]$text) {
    try { $msg = $text | ConvertFrom-Json } catch { return }
    if ($msg.type -ne 'cursor') { return }
    $S.RemoteAt = [DateTime]::Now
    $S.RemoteX = [double]$msg.x; $S.RemoteY = [double]$msg.y
    $S.RemoteInside = [bool]$msg.inside
    $S.RemoteName = if ($msg.name) { [string]$msg.name } else { 'Editor' }
}

# Non-blocking socket pump, called from the timer: poll the connect / receive tasks.
function Pump-Socket {
    if (-not $S.Ws) {
        if ([DateTime]::Now -lt $S.NextConnect) { return }
        $S.Ws = New-Object System.Net.WebSockets.ClientWebSocket
        $S.ConnectTask = $S.Ws.ConnectAsync([Uri]$Url, [Threading.CancellationToken]::None)
        Set-Status "Connecting to $Url"
        return
    }
    if ($S.ConnectTask) {
        if (-not $S.ConnectTask.IsCompleted) { return }
        if ($S.ConnectTask.IsFaulted -or $S.Ws.State -ne [System.Net.WebSockets.WebSocketState]::Open) { Reset-Socket 'connect failed'; return }
        $S.ConnectTask = $null
    }
    if ($S.Ws.State -ne [System.Net.WebSockets.WebSocketState]::Open) { Reset-Socket 'closed'; return }
    try {
        for ($i = 0; $i -lt 50; $i++) {
            if (-not $S.RecvTask) {
                $seg = New-Object 'System.ArraySegment[byte]' -ArgumentList (, $RecvBuf)
                $S.RecvTask = $S.Ws.ReceiveAsync($seg, [Threading.CancellationToken]::None)
            }
            if (-not $S.RecvTask.IsCompleted) { break }
            $res = $S.RecvTask.Result
            $S.RecvTask = $null
            if ($res.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) { Reset-Socket 'relay closed'; return }
            $S.RecvText += [Text.Encoding]::UTF8.GetString($RecvBuf, 0, $res.Count)
            if ($res.EndOfMessage) { $t = $S.RecvText; $S.RecvText = ''; On-Message $t }
        }
    } catch { Reset-Socket 'receive error'; return }
}

# ---------- Tick ----------
$tick = {
    try {
        Update-Premiere
        if ($S.Premiere -eq [IntPtr]::Zero) { $overlay.Visibility = 'Hidden'; Set-Status 'Premiere not found. Open Premiere Pro.'; return }
        $r = [PcWin]::Frame($S.Premiere)
        Sync-Overlay $r
        $front = (-not [PcWin]::IsIconic($S.Premiere)) -and (Test-PremiereInFront)
        $overlay.Visibility = if ($front) { 'Visible' } else { 'Hidden' }

        $p = New-Object PcWin+POINT
        [void][PcWin]::GetCursorPos([ref]$p)
        $w = [double]($r.Right - $r.Left); $h = [double]($r.Bottom - $r.Top)
        if ($w -le 0 -or $h -le 0) { return }
        $nx = ($p.X - $r.Left) / $w; $ny = ($p.Y - $r.Top) / $h
        $inside = $front -and $nx -ge 0 -and $nx -le 1 -and $ny -ge 0 -and $ny -le 1
        $nx = [Math]::Min(1.0, [Math]::Max(0.0, $nx)); $ny = [Math]::Min(1.0, [Math]::Max(0.0, $ny))

        if ($Loopback) {
            # Round-trip through the normalized value, exactly as the other laptop would draw it.
            $rx = [Math]::Round($nx, 4); $ry = [Math]::Round($ny, 4)
            $ring.Visibility = if ($inside) { 'Visible' } else { 'Hidden' }
            Move-ToNormalized $ring $rx $ry -17 -17
            Set-Status ("Loopback probe: x {0:N3}  y {1:N3}  scale {2}  frame {3}x{4}" -f $rx, $ry, $S.Scale, $w, $h)
            return
        }

        Pump-Socket
        if ($S.Ws -and $S.Ws.State -eq [System.Net.WebSockets.WebSocketState]::Open -and -not $S.ConnectTask) {
            $json = '{"type":"cursor","name":' + (ConvertTo-Json $Name -Compress) +
                ',"x":' + [Math]::Round($nx, 4).ToString([Globalization.CultureInfo]::InvariantCulture) +
                ',"y":' + [Math]::Round($ny, 4).ToString([Globalization.CultureInfo]::InvariantCulture) +
                ',"inside":' + $inside.ToString().ToLower() + '}'
            # Send on change, plus a 1 s keepalive so the other side knows we're still here.
            if ($json -ne $S.LastSent -or ([DateTime]::Now - $S.LastSentAt).TotalSeconds -ge 1) {
                if (Send-Json $json) { $S.LastSent = $json; $S.LastSentAt = [DateTime]::Now }
            }
            $age = ([DateTime]::Now - $S.RemoteAt).TotalSeconds
            if ($age -lt 3) { Set-Status "Connected as $Name. Seeing $($S.RemoteName)." }
            else { Set-Status "Connected as $Name to $Url. Waiting for the other cursor." }
        }

        $show = $S.RemoteInside -and ([DateTime]::Now - $S.RemoteAt).TotalSeconds -lt 3
        $ptr.Visibility = if ($show) { 'Visible' } else { 'Hidden' }
        if ($show) {
            if ($label.Text -ne $S.RemoteName) { $label.Text = $S.RemoteName }
            Move-ToNormalized $ptr $S.RemoteX $S.RemoteY 0 0
        }
    } catch {
        Set-Status ('Error: ' + $_.Exception.Message)
    }
}

# ---------- Run ----------
$app = New-Object System.Windows.Application
$app.ShutdownMode = 'OnMainWindowClose'
$overlay.Show()
$S.Scale = [Windows.PresentationSource]::FromVisual($overlay).CompositionTarget.TransformToDevice.M11
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds([Math]::Max(10, [int](1000 / $Hz)))
$timer.Add_Tick($tick)
$timer.Start()
$control.Add_Closed({ $timer.Stop(); if ($S.Ws) { try { $S.Ws.Dispose() } catch { } }; $overlay.Close() })
[void]$app.Run($control)
