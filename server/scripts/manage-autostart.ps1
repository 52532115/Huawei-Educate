<#
SafeTAcademy AI backend - Windows autostart via Task Scheduler.

Why Task Scheduler instead of a service wrapper (NSSM / WinSW): this project is
deliberately dependency-free on the server side - the component that holds the
vendor API keys does not pull anything from the supply chain. schtasks ships
with Windows, so nothing new enters the picture.

Usage (no admin rights needed - the task runs as the current user):

  powershell -ExecutionPolicy Bypass -File scripts\manage-autostart.ps1 -Action Install
  powershell -ExecutionPolicy Bypass -File scripts\manage-autostart.ps1 -Action Status
  powershell -ExecutionPolicy Bypass -File scripts\manage-autostart.ps1 -Action Start
  powershell -ExecutionPolicy Bypass -File scripts\manage-autostart.ps1 -Action Stop
  powershell -ExecutionPolicy Bypass -File scripts\manage-autostart.ps1 -Action Uninstall

Design notes worth keeping:

  * Trigger is AT LOGON, not at boot. Running at boot without a logon means
    either storing the account password or running as SYSTEM; both grant more
    privilege than this service needs. On a developer machine you log in anyway.
    See README if you really need the boot-time variant.

  * ExecutionTimeLimit is set to unlimited. Task Scheduler defaults to 3 days -
    leave that alone and the backend silently dies on day 4.

  * MultipleInstances = IgnoreNew. A second logon (or RDP reconnect) must not
    start a second copy; the runner also refuses to start when the port is busy,
    but belt and braces.
#>

[CmdletBinding()]
param(
    [ValidateSet('Install', 'Uninstall', 'Status', 'Start', 'Stop')]
    [string]$Action = 'Status',

    # How often the watchdog re-runs the action. Only read by -Action Install.
    [int]$WatchdogMinutes = 5
)

$ErrorActionPreference = 'Stop'

# Keep this string stable: it is the handle users type to manage the task.
$TaskName    = 'SafeTAcademy AI Backend'
$ServerDir   = Split-Path -Parent $PSScriptRoot
$ServeScript = Join-Path $PSScriptRoot 'serve.ps1'
$LogFile     = Join-Path $ServerDir 'logs\backend.log'

function Get-PowerShellExe {
    $cmd = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
}

function Get-ConfiguredPort {
    $envFile = Join-Path $ServerDir '.env'
    if (Test-Path -LiteralPath $envFile) {
        foreach ($raw in [System.IO.File]::ReadAllLines($envFile)) {
            $line = $raw.Trim()
            if ($line.StartsWith('PORT=')) {
                $parsed = 0
                $value = $line.Substring(5).Trim().Trim('"').Trim("'")
                if ([int]::TryParse($value, [ref]$parsed) -and $parsed -gt 0) { return $parsed }
            }
        }
    }
    return 8787
}

function Get-LanAddress {
    # 手机/模拟器要连的那张网卡 = 默认路由所在的那张。
    #
    # 不能用"第一个非回环地址"顶替：这台机器同时装着 VirtualBox 的 Host-Only
    # 网卡（192.168.56.x），它是虚拟的，填进 App 永远连不上。走默认路由就没有
    # 这个歧义 —— 那是系统自己认定的出口。
    try {
        $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
            Sort-Object RouteMetric | Select-Object -First 1
        if ($route) {
            $addr = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $route.InterfaceIndex -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($addr) { return $addr.IPAddress }
        }
    } catch { }
    return ''
}

function Get-FullUserName {
    return "$env:USERDOMAIN\$env:USERNAME"
}

# ------------------------------------------------------------------ actions

function Install-Task {
    if (-not (Test-Path -LiteralPath $ServeScript)) {
        throw "Cannot find $ServeScript"
    }

    $psExe = Get-PowerShellExe
    $argument = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $ServeScript + '"'

    $taskAction = New-ScheduledTaskAction -Execute $psExe -Argument $argument -WorkingDirectory $ServerDir

    # Two triggers on purpose. They are NOT interchangeable, and this cost a
    # round of measurement to learn (2026-09-19):
    #
    #   * logon  — starts it when you log in, once.
    #   * repeat — the watchdog. It has to be its own trigger with its own start
    #     boundary, because a **logon trigger's repetition window is anchored to
    #     the logon event**. Attaching the repetition to the logon trigger
    #     registers cleanly and reports `Repetition.Interval = PT1M`, yet never
    #     fires in a session that logged on before the task was installed —
    #     i.e. it looks installed and does nothing. Measured: killed the service
    #     and waited 150 s; it stayed down.
    $logonTrigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    # Give the network stack a moment: the server talks to the vendors right away.
    $logonTrigger.Delay = 'PT30S'

    # Deliberately NO -RepetitionDuration: omitting it is what means "repeat
    # indefinitely". Passing [TimeSpan]::MaxValue looks like the obvious way to
    # say that and is rejected — `Register-ScheduledTask : 任务 XML 包含格式不正确
    # 或超出范围的值 … Duration:P99999999DT23H59M59S` (measured, same day).
    $watchdogTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
        -RepetitionInterval (New-TimeSpan -Minutes $WatchdogMinutes)

    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -MultipleInstances IgnoreNew `
        -RestartCount 3 `
        -RestartInterval (New-TimeSpan -Minutes 1) `
        -ExecutionTimeLimit (New-TimeSpan -Seconds 0)

    $principal = New-ScheduledTaskPrincipal -UserId (Get-FullUserName) -LogonType Interactive -RunLevel Limited

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $taskAction `
        -Trigger @($logonTrigger, $watchdogTrigger) `
        -Settings $settings `
        -Principal $principal `
        -Description 'SafeTAcademy AI backend (chat + embedding proxy). Starts at logon; writes logs\backend.log.' `
        -Force | Out-Null

    # Verify by reading the task back before claiming anything.
    #
    # `Register-ScheduledTask` reports a bad definition as a NON-terminating error,
    # so `$ErrorActionPreference = 'Stop'` does not stop the script: execution fell
    # straight through to the success messages below and printed "已安装开机自启任务"
    # for a task that was never created (2026-09-19, Duration 取值越界). The next
    # `-Action Start` then said "尚未安装" — the only honest line in the whole run.
    # A guard that cannot fail is worse than no guard.
    if (-not (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)) {
        throw "注册没有成功：任务 $TaskName 读不回来。真正的原因在上面那条错误里。"
    }

    # Also confirm the watchdog survived registration as its own trigger. A
    # repetition attached to the logon trigger passes every one of the checks
    # above while never firing, so checking "the task exists" is not enough.
    $registered = Get-ScheduledTask -TaskName $TaskName
    $repeating = @($registered.Triggers | Where-Object { $_.Repetition.Interval -and $_.Repetition.Interval -ne 'PT0S' })
    if ($repeating.Count -eq 0) {
        throw '看门狗没有生效：没有任何触发器的重复间隔被注册上。'
    }

    Write-Host '已安装开机自启任务。' -ForegroundColor Green
    Write-Host "  任务名   : $TaskName"
    Write-Host "  触发     : 登录后 30 秒（当前用户 $(Get-FullUserName)）"
    Write-Host "  看门狗   : 每 $WatchdogMinutes 分钟重跑一次；端口已被占用时立即退出（幂等）"
    Write-Host "  运行     : $psExe"
    Write-Host "  脚本     : $ServeScript"
    Write-Host "  日志     : $LogFile"
    Write-Host ''
    Write-Host '现在立即启动一次（不用等下次登录）：'
    Write-Host "  powershell -ExecutionPolicy Bypass -File scripts\manage-autostart.ps1 -Action Start"
}

function Uninstall-Task {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $task) {
        Write-Host '该任务不存在，无需卸载。'
        return
    }
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host '已卸载开机自启任务（日志文件保留，可自行删除 logs\ 目录）。' -ForegroundColor Green
}

function Show-Status {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $task) {
        Write-Host '未安装。运行 -Action Install 来安装。' -ForegroundColor Yellow
    } else {
        $info = Get-ScheduledTaskInfo -TaskName $TaskName
        Write-Host '任务状态' -ForegroundColor Cyan
        Write-Host "  任务名       : $TaskName"
        Write-Host "  状态         : $($task.State)"
        Write-Host "  上次运行     : $($info.LastRunTime)"
        Write-Host "  上次结果     : $($info.LastTaskResult)"
        Write-Host "  下次运行     : $($info.NextRunTime)"
    }

    $port = Get-ConfiguredPort
    $busy = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    Write-Host ''
    Write-Host '服务状态' -ForegroundColor Cyan
    if ($busy) {
        $pids = ($busy | Select-Object -ExpandProperty OwningProcess -Unique) -join ', '
        Write-Host "  端口 $port : 正在监听（pid $pids）" -ForegroundColor Green
    } else {
        Write-Host "  端口 $port : 无人监听" -ForegroundColor Yellow
    }

    if (Test-Path -LiteralPath $LogFile) {
        $size = [math]::Round((Get-Item -LiteralPath $LogFile).Length / 1KB, 1)
        Write-Host "  日志         : $LogFile ($size KB)"
    } else {
        Write-Host "  日志         : (还没有生成，服务尚未运行过)"
    }

    # 局域网 IP 会随 DHCP 变（这台机器实测从 10.134.41.230 变成过 10.134.41.72），
    # 而 App 里存的是上一次填的那一串。地址一过期，手机侧的现象就是"连不上后端"，
    # 但服务其实好端端在跑 —— 于是最容易怀疑错方向。所以把当前该填的那一行直接
    # 打印出来，让这里成为唯一的出处。
    Write-Host ''
    Write-Host 'App 里要填的地址' -ForegroundColor Cyan
    $lan = Get-LanAddress
    if ($lan.Length -gt 0) {
        Write-Host "  http://${lan}:$port" -ForegroundColor Green
        Write-Host '  填进 App 的「后端地址」；令牌用 server/.env 里的 APP_TOKEN。'
        Write-Host '  IP 会随网络变化，以这段输出为准，别照抄以前记下的。' -ForegroundColor Yellow
    } else {
        Write-Host '  没找到默认路由网卡 —— 确认电脑已连上网络后重试。' -ForegroundColor Yellow
    }
}

function Start-Task {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $task) {
        Write-Host '尚未安装，请先运行 -Action Install。' -ForegroundColor Yellow
        return
    }
    Start-ScheduledTask -TaskName $TaskName
    Write-Host '已请求启动。等两秒后看状态：' -ForegroundColor Green
    Start-Sleep -Seconds 2
    Show-Status
}

function Stop-Task {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $task) {
        Write-Host '尚未安装。' -ForegroundColor Yellow
        return
    }
    Stop-ScheduledTask -TaskName $TaskName
    Write-Host '已请求停止。' -ForegroundColor Green
}

# ------------------------------------------------------------------ main

switch ($Action) {
    'Install'   { Install-Task }
    'Uninstall' { Uninstall-Task }
    'Status'    { Show-Status }
    'Start'     { Start-Task }
    'Stop'      { Stop-Task }
}
