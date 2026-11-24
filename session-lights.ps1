# Floating always-on-top status lights, one per running Claude Code session.
# Source: ~/.claude/sessions/<pid>.json, written by Claude Code itself (status: busy | waiting | idle).
param(
    [switch]$Probe,         # print each session's resolved state and exit (no window)
    [string]$SessionsDir,   # read session files from another folder (testing with edited copies)
    [switch]$Stop,          # ask the running instance to quit cleanly (removes its tray icon)
    [switch]$Restart        # stop the running instance, then start this one
)
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# A named event lets a new process ask the running one to quit cleanly. Killing the process
# instead leaves a dead tray icon behind until the mouse passes over it.
$quitEvent = New-Object System.Threading.EventWaitHandle($false, 'AutoReset', 'Local\ClaudeSessionLightsQuit')
if ($Stop -or $Restart) {
    [void]$quitEvent.Set()
    if ($Stop) { exit }
}

if (-not $Probe) {
    $created = $false
    $mutex = New-Object System.Threading.Mutex($false, 'Local\ClaudeSessionLights')
    # With -Restart, wait for the old instance to let go; otherwise a second copy just leaves.
    try { $created = $mutex.WaitOne($(if ($Restart) { 8000 } else { 0 })) } catch [System.Threading.AbandonedMutexException] { $created = $true }
    if (-not $created) { exit }
    [void]$quitEvent.Reset()   # a stale quit request must not close this new instance
}

$sessDir  = if ($SessionsDir) { $SessionsDir } else { Join-Path $env:USERPROFILE '.claude\sessions' }
$cfgPath  = Join-Path $PSScriptRoot 'settings.json'
$cfg = [pscustomobject]@{ left = 40; top = 40; hideNames = $false; compact = $false; sound = $true; hidden = $false; mainDir = $null; lang = 'auto' }
if (Test-Path $cfgPath) {
    try {
        $saved = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($p in $saved.PSObject.Properties) { $cfg | Add-Member -Force -NotePropertyName $p.Name -NotePropertyValue $p.Value }
    } catch {}
}
# Sessions whose name is hidden one by one, keyed by the desktop's stable session id.
$cfg | Add-Member -Force -NotePropertyName hiddenSessions -NotePropertyValue @($(if ($cfg.PSObject.Properties['hiddenSessions']) { $cfg.hiddenSessions }) | Where-Object { $_ })
function Get-SessionKey($s) { if ($s.hostSessionId) { [string]$s.hostSessionId } else { [string]$s.sessionId } }
function Test-NameHidden($s) { $cfg.hideNames -or ($cfg.hiddenSessions -contains (Get-SessionKey $s)) }
function Save-Cfg { try { $cfg | ConvertTo-Json | Set-Content $cfgPath -Encoding UTF8 } catch {} }

$strings = @{
    zh = @{
        busy = '运行中'; waiting = '等你处理'; idle = '空闲'; gone = '已中断'
        toTray = '收进托盘'; eyeTip = '显示/隐藏会话名'; rowEyeTip = '只隐藏 / 显示这个会话名'
        noQuestionText = '（有问题等你回答）'; planPending = '计划等你批准'
        actEdit = '正在编辑 {0}'; actRead = '正在读 {0}'; actRun = '正在运行：{0}'; actSearch = '正在搜索 {0}'
        actAgent = '子代理：{0}'; actWeb = '正在查网页'; actMcp = '正在调用 {0}'; actOther = '正在用 {0}'
        waitReply = '你的回复'; waitAnswer = '回答问题'; waitPlan = '批准计划'; subagentsBg = '子代理在后台跑'
        noClaude = '没找到 Claude 窗口'; splitView = '分屏中，没有切换'; noUi = '没读到 Claude 的界面，没有切换'
        notInSidebar = '侧栏里没找到这个会话'; ambiguous = '侧栏有同名会话，没有切换'; openFailed = '切换失败'
        sessionN = '会话 {0}'; askPrefix = '问：'; unreadTip = '刚跑完，还没看（点一下这行消掉）'
        goneTip = '运行中途消失了（崩溃或被关掉）'; subsTip = '子代理 {0} 个在跑'; empty = '没有运行中的会话'
        summary = 'Claude · 运行 {0} · 等你 {1} · 空闲 {2}'
        hideAll = '隐藏全部会话名'; compact = '只显示灯'; sound = '等你处理时提示音'; exit = '退出'
        showRowName = '显示这个会话名'; hideRowName = '隐藏这个会话名'; showWindow = '显示窗口'; hideNames = '隐藏会话名'
    }
    en = @{
        busy = 'Working'; waiting = 'Waiting for you'; idle = 'Idle'; gone = 'Interrupted'
        toTray = 'Hide to tray'; eyeTip = 'Show / hide session names'; rowEyeTip = 'Hide / show this session name only'
        noQuestionText = '(a question is waiting for you)'; planPending = 'A plan is waiting for approval'
        actEdit = 'Editing {0}'; actRead = 'Reading {0}'; actRun = 'Running: {0}'; actSearch = 'Searching {0}'
        actAgent = 'Subagent: {0}'; actWeb = 'Browsing the web'; actMcp = 'Calling {0}'; actOther = 'Using {0}'
        waitReply = 'your reply'; waitAnswer = 'an answer'; waitPlan = 'plan approval'; subagentsBg = 'Subagents working in the background'
        noClaude = 'Claude window not found'; splitView = 'Split view: not switching'; noUi = "Couldn't read Claude's window: not switching"
        notInSidebar = 'Session not found in the sidebar'; ambiguous = 'Several sidebar matches: not switching'; openFailed = 'Could not open the session'
        sessionN = 'Session {0}'; askPrefix = 'Q: '; unreadTip = 'Just finished, not seen yet (click the row to clear)'
        goneTip = 'Vanished while working (crashed or closed)'; subsTip = '{0} subagent(s) working'; empty = 'No running sessions'
        summary = 'Claude · working {0} · waiting {1} · idle {2}'
        hideAll = 'Hide all session names'; compact = 'Lights only'; sound = 'Chime when waiting'; exit = 'Exit'
        showRowName = 'Show this session name'; hideRowName = 'Hide this session name'; showWindow = 'Show window'; hideNames = 'Hide session names'
    }
}
$lang = if ($cfg.lang -in 'zh', 'en') { $cfg.lang } elseif ([Globalization.CultureInfo]::CurrentUICulture.Name -like 'zh*') { 'zh' } else { 'en' }
$UiText = $strings[$lang]

$conv = New-Object System.Windows.Media.BrushConverter
function Get-Brush([string]$hex) { $conv.ConvertFromString($hex) }

$states = @{
    busy    = @{ color = '#3B82F6'; label = $UiText.busy }
    waiting = @{ color = '#F59E0B'; label = $UiText.waiting }
    idle    = @{ color = '#22C55E'; label = $UiText.idle }
    gone    = @{ color = '#6B7280'; label = $UiText.gone }
}

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" SizeToContent="WidthAndHeight" ResizeMode="NoResize">
  <Border x:Name="Root" CornerRadius="10" Background="#E6181A20" BorderBrush="#33FFFFFF" BorderThickness="1" Padding="10,8">
    <StackPanel>
      <DockPanel x:Name="Header" Margin="0,0,0,4">
        <TextBlock x:Name="CloseBtn" DockPanel.Dock="Right" Text="&#xE8BB;" FontFamily="Segoe MDL2 Assets" Foreground="#99FFFFFF" FontSize="10" Margin="10,0,0,0" VerticalAlignment="Center" Cursor="Hand" Background="Transparent"/>
        <!-- Vector eye icon; the slash shows while names are hidden (Win10 icon font has no eye-off glyph). -->
        <Grid x:Name="EyeBtn" DockPanel.Dock="Right" Width="16" Height="16" Margin="10,0,0,0" VerticalAlignment="Center" Cursor="Hand" Background="Transparent">
          <Path Data="M1.5,8 C4,3.6 12,3.6 14.5,8 C12,12.4 4,12.4 1.5,8 Z" Stroke="#B3FFFFFF" StrokeThickness="1.3" StrokeLineJoin="Round"/>
          <Ellipse Width="4.6" Height="4.6" Fill="#B3FFFFFF"/>
          <Line x:Name="EyeSlash" X1="2.5" Y1="13.5" X2="13.5" Y2="2.5" Stroke="#B3FFFFFF" StrokeThickness="1.5" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
        </Grid>
        <TextBlock x:Name="Summary" Foreground="#CCFFFFFF" FontSize="11" FontFamily="Microsoft YaHei UI" VerticalAlignment="Center"/>
      </DockPanel>
      <StackPanel x:Name="Rows"/>
    </StackPanel>
  </Border>
</Window>
'@
$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$rows = $win.FindName('Rows'); $summary = $win.FindName('Summary')
$eye = $win.FindName('EyeBtn'); $eyeSlash = $win.FindName('EyeSlash'); $closeBtn = $win.FindName('CloseBtn')
$closeBtn.ToolTip = $UiText.toTray; $eye.ToolTip = $UiText.eyeTip
$vs = [System.Windows.SystemParameters]
if ($cfg.left -lt $vs::VirtualScreenLeft -or $cfg.left -gt $vs::VirtualScreenLeft + $vs::VirtualScreenWidth - 60 -or
    $cfg.top -lt $vs::VirtualScreenTop -or $cfg.top -gt $vs::VirtualScreenTop + $vs::VirtualScreenHeight - 40) { $cfg.left = 40; $cfg.top = 40 }
$win.Left = $cfg.left; $win.Top = $cfg.top

# Busy lights pulse from a wall-clock phase, so a row rebuild does not restart the pulse.
$script:busyDots = New-Object System.Collections.ArrayList
function Get-PulseOpacity { 0.25 + 0.75 * (0.5 + 0.5 * [math]::Cos([DateTime]::Now.TimeOfDay.TotalMilliseconds / 1600 * 2 * [math]::PI)) }

# Claude Code reports a turn that ended on a question as plain `idle`, so the transcript tail is checked.
$projDir = Join-Path $env:USERPROFILE '.claude\projects'
$script:transcriptPath = @{}   # sessionId -> transcript path
$script:askCache = @{}         # sessionId -> @{ key; asked }

function Find-Transcript($s) {
    $id = [string]$s.sessionId
    $p = $script:transcriptPath[$id]
    if ($p -and (Test-Path $p)) { return $p }
    $slug = ([string]$s.cwd) -replace '[:\\/]', '-'
    $p = Join-Path $projDir "$slug\$id.jsonl"
    if (-not (Test-Path $p)) {
        $hit = Get-ChildItem $projDir -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName "$id.jsonl" } | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $hit) { return $null }
        $p = $hit
    }
    $script:transcriptPath[$id] = $p
    $p
}

function Read-Shared([string]$path) {
    $fs = [IO.File]::Open($path, 'Open', 'Read', 'ReadWrite, Delete')
    try { (New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)).ReadToEnd() } finally { $fs.Dispose() }
}

function Read-Tail([string]$path, [int]$bytes) {
    $fs = [IO.File]::Open($path, 'Open', 'Read', 'ReadWrite, Delete')
    try {
        $start = [math]::Max(0, $fs.Length - $bytes)
        $fs.Seek($start, 'Begin') | Out-Null
        $buf = New-Object byte[] ($fs.Length - $start)
        $read = $fs.Read($buf, 0, $buf.Length)
        $text = [Text.Encoding]::UTF8.GetString($buf, 0, $read)
        $lines = $text -split "`n"
        if ($start -gt 0 -and $lines.Count -gt 1) { $lines = $lines[1..($lines.Count - 1)] }  # drop partial first line
        $lines
    } finally { $fs.Dispose() }
}

# AskUserQuestion input: { questions: [ { question, options, ... } ] }
function Get-QuestionText($in) {
    $qs = @($in.questions | ForEach-Object { [string]$_.question } | Where-Object { $_ })
    if ($qs.Count) { $qs -join "`n" } else { $UiText.noQuestionText }
}

function Test-AskedUser($s) {
    $path = Find-Transcript $s
    if (-not $path) { return $false }
    $fi = Get-Item $path
    $key = "$($fi.Length)|$($fi.LastWriteTimeUtc.Ticks)"
    $hit = $script:askCache[[string]$s.sessionId]
    if ($hit -and $hit.key -eq $key) { return $hit.asked }

    $asked = $null   # the question text once found
    $askId = $null; $textId = $null
    $results = @{}; $lastText = $null; $lastStop = $null; $sawAssistant = $false
    try { $lines = Read-Tail $path 524288 } catch { $lines = @() }
    for ($k = $lines.Count - 1; $k -ge 0; $k--) {
        $line = $lines[$k].Trim()
        if (-not $line) { continue }
        try { $j = $line | ConvertFrom-Json } catch { continue }   # oversized tool output lines are skipped
        if ($j.isSidechain) { continue }   # subagent traffic is not the main conversation
        $c = $j.message.content
        if ($j.type -eq 'user') {
            # An Esc interrupt ends the turn without a question.
            if ($line -match '"text":"\[Request interrupted by user') { $lastText = $null; break }
            if ($c -is [array] -and ($c | Where-Object { $_.type -eq 'tool_result' })) {
                foreach ($b in $c) { if ($b.type -eq 'tool_result') { $results[[string]$b.tool_use_id] = $true } }
                continue
            }
            if ($j.isMeta) { continue }
            break   # the user's own prompt: everything newer is the current turn
        }
        if ($j.type -ne 'assistant' -or -not ($c -is [array])) { continue }
        if (-not $sawAssistant) { $sawAssistant = $true; $lastStop = [string]$j.message.stop_reason }
        for ($b = $c.Count - 1; $b -ge 0; $b--) {
            $blk = $c[$b]
            if ($blk.type -eq 'tool_use') {
                if ($blk.name -eq 'AskUserQuestion' -and -not $results.ContainsKey([string]$blk.id)) { $asked = Get-QuestionText $blk.input; $askId = [string]$blk.id }
                if ($blk.name -eq 'ExitPlanMode' -and -not $results.ContainsKey([string]$blk.id)) { $asked = $UiText.planPending; $askId = [string]$blk.id }
                if ($blk.name -like '*ccd_turn__wrap_up' -and $blk.input.ask) { $asked = [string]$blk.input.ask; $askId = [string]$blk.id }
            } elseif ($blk.type -eq 'text' -and $null -eq $lastText -and $blk.text.Trim()) {
                $lastText = $blk.text.Trim(); $textId = [string]$j.uuid
            }
        }
        if ($asked) { break }
    }
    # The closing-text rule needs a finished turn: a reply that stopped for a tool call is not a question.
    if (-not $asked -and $lastText -and $lastStop -ne 'tool_use') {
        $last = ($lastText -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 1).Trim()
        if ($last -match '[？?]\s*\**\s*$') { $asked = ($last -replace '\*\*', '').Trim(); $askId = $textId }
    }
    $script:askCache[[string]$s.sessionId] = @{ key = $key; asked = $asked; id = $askId }
    $asked
}

# Busy session details from the transcript tail, cached by file size + time.
$script:busyCache = @{}
function Format-Action($blk) {
    $in = $blk.input
    $leaf = { param($f) if ($f) { Split-Path ([string]$f) -Leaf } else { '' } }
    $short = { param($t) $t = ([string]$t -replace '\s+', ' ').Trim(); if ($t.Length -gt 60) { $t.Substring(0, 60) + '…' } else { $t } }
    switch -Regex ([string]$blk.name) {
        '^(Edit|MultiEdit|Write|NotebookEdit)$' { return $UiText.actEdit -f (& $leaf $in.file_path) }
        '^Read$'                                { return $UiText.actRead -f (& $leaf $in.file_path) }
        '^(Bash|PowerShell)$'                   { return $UiText.actRun -f (& $short $(if ($in.description) { $in.description } else { $in.command })) }
        '^(Grep|Glob)$'                         { return $UiText.actSearch -f (& $short $in.pattern) }
        '^(Agent|Task)$'                        { return $UiText.actAgent -f (& $short $in.description) }
        '^(WebFetch|WebSearch)$'                { return $UiText.actWeb }
        '^mcp__'                                { return $UiText.actMcp -f (([string]$blk.name -split '__')[-1]) }
        default                                 { return $UiText.actOther -f $blk.name }
    }
}
function Get-BusyInfo($s) {
    $path = Find-Transcript $s
    if (-not $path) { return $null }
    $fi = Get-Item $path
    $key = "$($fi.Length)|$($fi.LastWriteTimeUtc.Ticks)"
    $hit = $script:busyCache[[string]$s.sessionId]
    # A busy transcript changes constantly, so it is re-read at most every 3s.
    if ($hit -and ($hit.key -eq $key -or ([DateTime]::Now - $hit.at).TotalSeconds -lt 3)) { return $hit.info }
    $info = @{ question = $null; action = $null }
    $results = @{}
    $lines = @(Read-Tail $path 65536 | Where-Object { $_.Trim() })
    $stop = [math]::Max(0, $lines.Count - 60)
    for ($k = $lines.Count - 1; $k -ge $stop; $k--) {
        $line = $lines[$k]
        # Cheap text checks first: only assistant lines with a tool call are worth parsing.
        if ($line -match '"isSidechain":true') { continue }
        if ($line -match '"type":"user"') {
            $ms = [regex]::Matches($line, '"tool_use_id":"([^"]+)"')
            if ($ms.Count -eq 0 -and $line -notmatch '"isMeta":true') { break }   # the user's own prompt starts this round
            foreach ($m in $ms) { $results[$m.Groups[1].Value] = $true }
            continue
        }
        if ($line -notmatch '"type":"assistant"' -or $line -notmatch '"type":"tool_use"') { continue }
        try { $j = $line | ConvertFrom-Json } catch { continue }
        $c = @($j.message.content)
        $tool = $null
        for ($b = $c.Count - 1; $b -ge 0; $b--) { if ($c[$b].type -eq 'tool_use') { $tool = $c[$b]; break } }
        if (-not $tool) { continue }
        if (-not $results.ContainsKey([string]$tool.id)) {
            if ($tool.name -eq 'AskUserQuestion') { $info.question = Get-QuestionText $tool.input; $info.qid = [string]$tool.id }
            elseif ($tool.name -eq 'ExitPlanMode') { $info.question = $UiText.planPending; $info.qid = [string]$tool.id }
        }
        $info.action = Format-Action $tool
        break
    }
    $script:busyCache[[string]$s.sessionId] = @{ key = $key; info = $info; at = [DateTime]::Now }
    $info
}
# Subagents still writing their transcript in the last 15s (re-counted every 5s).
$script:subCache = @{}
function Get-SubagentCount($s) {
    $hit = $script:subCache[[string]$s.sessionId]
    if ($hit -and ([DateTime]::Now - $hit.at).TotalSeconds -lt 5) { return $hit.n }
    $n = Get-SubagentCountNow $s
    $script:subCache[[string]$s.sessionId] = @{ n = $n; at = [DateTime]::Now }
    $n
}
function Get-SubagentCountNow($s) {
    $path = Find-Transcript $s
    if (-not $path) { return 0 }
    $dir = Join-Path (Split-Path $path) "$($s.sessionId)\subagents"
    if (-not (Test-Path $dir)) { return 0 }
    $cut = [DateTime]::Now.AddSeconds(-15)
    @(Get-ChildItem $dir -Filter 'agent-*.jsonl' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $cut }).Count
}

# Process lookups cost ~30ms each, so liveness is re-checked every 15s per pid.
$script:aliveCache = @{}
# The recorded procStart (FILETIME) must match the live process, so a recycled pid is not taken for the session.
function Test-PidAlive([int]$procId, [string]$procStart) {
    $key = "$procId|$procStart"
    $hit = $script:aliveCache[$key]
    if ($hit -and ([DateTime]::Now - $hit.at).TotalSeconds -lt 15) { return $hit.alive }
    $p = Get-Process -Id $procId -ErrorAction SilentlyContinue
    $alive = [bool]$p
    if ($p -and $procStart) {
        try {
            $diff = [math]::Abs(($p.StartTime - [DateTime]::FromFileTime([long]$procStart)).TotalSeconds)
            if ($diff -gt 2) { $alive = $false }
        } catch {}   # StartTime unreadable (e.g. elevated process): keep the pid check alone
    }
    $script:aliveCache[$key] = @{ at = [DateTime]::Now; alive = $alive }
    $alive
}

function Get-Sessions {
    $list = @()
    foreach ($f in Get-ChildItem $sessDir -Filter '*.json' -ErrorAction SilentlyContinue) {
        try { $d = Read-Shared $f.FullName | ConvertFrom-Json; if (-not $d) { throw 'empty' } }
        catch {
            $fid = [int]($f.BaseName -replace '\D', '0')
            $old = if ($script:lastObj) { $script:lastObj[$fid] } else { $null }
            if ($old -and -not $script:readFails[$fid]) { $list += $old }   # caught mid-rewrite: keep the last good state once
            if ($script:readFails) { $script:readFails[$fid] = $true }
            continue
        }
        if ($script:readFails) { $script:readFails.Remove([int]($f.BaseName -replace '\D', '0')) }
        $pidNum = 0   # a missing or malformed pid skips the file; pid 0 would match the System Idle process
        if ($d.pid -is [array] -or -not [int]::TryParse([string]$d.pid, [ref]$pidNum) -or $pidNum -le 0) { continue }
        $d.pid = $pidNum
        if (-not (Test-PidAlive $pidNum ([string]$d.procStart))) { continue }  # stale file: dead or recycled pid
        if ($d.PSObject.Properties['spare'] -and $d.spare) { continue } # pre-warmed spare, not a real session
        if (-not $d.status) { continue }
        # An idle session whose last turn ended on a question is waiting on the user too.
        if ($d.status -eq 'idle') {
            try {
                $q = Test-AskedUser $d
                if ($q) {
                    $d.status = 'waiting'
                    $d | Add-Member -Force -NotePropertyName waitingFor -NotePropertyValue $UiText.waitReply
                    $d | Add-Member -Force -NotePropertyName question -NotePropertyValue $q
                    $d | Add-Member -Force -NotePropertyName questionId -NotePropertyValue $script:askCache[[string]$d.sessionId].id
                } else {
                    # The turn has ended but background subagents are still working: not idle.
                    $subs = Get-SubagentCountNow $d
                    if ($subs -gt 0) {
                        $d.status = 'busy'
                        $d | Add-Member -Force -NotePropertyName subagents -NotePropertyValue $subs
                        $d | Add-Member -Force -NotePropertyName action -NotePropertyValue $UiText.subagentsBg
                    }
                }
            } catch {}
        } elseif ($d.status -eq 'waiting') {
            try {
                $info = Get-BusyInfo $d
                if ($info -and $info.question) {
                    $d | Add-Member -Force -NotePropertyName question -NotePropertyValue $info.question
                    $d | Add-Member -Force -NotePropertyName questionId -NotePropertyValue $info.qid
                }
            } catch {}
        } elseif ($d.status -eq 'busy') {
            # A pending question or plan approval may still report busy; otherwise show what it is doing.
            try {
                $info = Get-BusyInfo $d
                if ($info -and $info.question) {
                    $d.status = 'waiting'
                    $d | Add-Member -Force -NotePropertyName waitingFor -NotePropertyValue $(if ($info.question -eq $UiText.planPending) { $UiText.waitPlan } else { $UiText.waitAnswer })
                    $d | Add-Member -Force -NotePropertyName question -NotePropertyValue $info.question
                    $d | Add-Member -Force -NotePropertyName questionId -NotePropertyValue $info.qid
                } elseif ($info -and $info.action) {
                    $d | Add-Member -Force -NotePropertyName action -NotePropertyValue $info.action
                }
                $d | Add-Member -Force -NotePropertyName subagents -NotePropertyValue (Get-SubagentCount $d)
            } catch {}
        }
        $list += $d
    }
    # Stable order: oldest session first, so hidden-name numbering does not jump around.
    @($list | Sort-Object startedAt)
}

# --- Click a row: bring Claude forward and open that session -------------------------------------
# Local Code-tab sessions have no deep link (claude://claude.ai/code/local_* opens a blank window),
# so the sidebar entry is found via UI Automation and invoked.
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
Add-Type -Namespace SessionLights -Name Mem -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetCurrentProcess();
[DllImport("kernel32.dll")] public static extern bool SetProcessWorkingSetSize(IntPtr h, IntPtr min, IntPtr max);
'@
Add-Type -Namespace SessionLights -Name U32 -MemberDefinition @'
[DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr h);
[DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
[DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
[DllImport("user32.dll")] static extern bool AttachThreadInput(uint a, uint b, bool attach);
[DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
public static bool Activate(IntPtr h) {
    if (IsIconic(h)) ShowWindow(h, 9);   // SW_RESTORE
    uint me = GetCurrentThreadId(), fg = GetWindowThreadProcessId(GetForegroundWindow(), IntPtr.Zero);
    bool att = fg != me && AttachThreadInput(me, fg, true);   // share the foreground thread's input state
    BringWindowToTop(h); bool ok = SetForegroundWindow(h);
    if (att) AttachThreadInput(me, fg, false);
    return ok;
}
'@

function Open-ClaudeSession([string]$name) {
    $p = Get-Process -Name 'claude' -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -eq 'Claude' } | Select-Object -First 1
    if (-not $p) { return $UiText.noClaude }
    $h = $p.MainWindowHandle
    [void][SessionLights.U32]::Activate($h)
    if (-not $name) { return $null }

    $AE = [System.Windows.Automation.AutomationElement]
    $root = $AE::FromHandle($h)
    $btnType = New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)
    $editType = New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::Edit)
    $buttons = $null; $prompts = @()
    for ($try = 0; $try -lt 2; $try++) {   # Chromium builds its accessibility tree on the first query
        $buttons = @($root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnType))
        $prompts = @($root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $editType) | Where-Object { $_.Current.Name -eq 'Prompt' })
        if ($prompts.Count -gt 0) { break }
        if ($try -eq 0) { Start-Sleep -Milliseconds 1500 }
    }
    # Every pane in split view has a "Close split view" button and its own prompt box, titled or not.
    $panes = @($buttons | Where-Object { $_.Current.Name -like '*, rename session' } | ForEach-Object { $_.Current.Name -replace ', rename session$', '' })
    $splitBtns = @($buttons | Where-Object { $_.Current.Name -eq 'Close split view' })
    if ($splitBtns.Count -gt 0 -or $prompts.Count -ge 2 -or $panes.Count -ge 2) { return $UiText.splitView }
    if ($prompts.Count -eq 0) { return $UiText.noUi }
    if ($panes.Count -eq 1 -and $panes[0] -eq $name) { return $null }

    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $side = @($buttons | Where-Object {
        $par = $walker.GetParent($_)
        $par -and $par.Current.ClassName -like '*df-nav-scroll-box*'
    })
    # Sidebar names may carry a status suffix; only the suffixes Claude is known to add count.
    $re = '^' + [regex]::Escape($name) + ' (Running|Started by Claude from .+|Open · .+)$'
    $hits = @($side | Where-Object {
        $n = $_.Current.Name
        $n -eq $name -or ($n -match $re -and -not ($script:liveNames -contains $n))
    })
    if ($hits.Count -ne 1) { return $(if ($hits.Count -eq 0) { $UiText.notInSidebar } else { $UiText.ambiguous }) }
    try { $hits[0].GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() } catch { return $UiText.openFailed }
    $null
}

if ($Probe) {
    Get-Sessions | ForEach-Object { "$($_.status)`t$($_.waitingFor)`t$($_.name)`t$($_.question)" }
    exit
}

# Transitions: flash + sound when a session starts waiting; unread dot when a turn finishes.
$script:prevStatus = @{}   # pid -> last resolved status
$script:unread = @{}       # pid -> $true until clicked or the session works again
$script:flashUntil = @{}   # pid -> DateTime the row stops flashing
$script:flashRows = New-Object System.Collections.ArrayList
$flashSeconds = 2.4        # three 0.8s pulses
$script:waitRounds = @{}   # "pid|statusUpdatedAt|question" -> @{ since; due }: one alert per round, 4s after it appears
$script:scans = 0
$script:readFails = @{}    # pid -> its session file failed to parse on the last poll
$script:lastObj = @{}      # pid -> last session object, to show an interrupted row after it vanishes
$script:ghosts = @{}       # pid -> @{ s; until }

function Update-Transitions($sessions) {
    $seen = @{}
    foreach ($s in $sessions) {
        $id = [int]$s.pid; $st = [string]$s.status; $seen[$id] = $true
        $script:ghosts.Remove($id)   # back again, so no interrupted row for it
        $prev = $script:prevStatus[$id]
        if ($prev -and $st -eq 'idle' -and $prev -eq 'busy') { $script:unread[$id] = $true }
        if ($st -eq 'waiting') {
            $qid = if ($s.PSObject.Properties['questionId']) { $s.questionId } else { $null }
            $round = if ($qid) { "$id|q|$qid" } elseif ($s.question) { "$id|q|$($s.question)" } else { "$id|t|$($s.statusUpdatedAt)" }
            $w = $script:waitRounds[$round]
            if (-not $w) { $w = @{ since = $null; due = ($script:scans -gt 0) }; $script:waitRounds[$round] = $w }
            if (-not $w.since) { $w.since = [DateTime]::Now }
            foreach ($k in @($script:waitRounds.Keys)) { if ($k -like "$id|*" -and $k -ne $round) { $script:waitRounds[$k].since = $null } }
            if ($w.due -and ([DateTime]::Now - $w.since).TotalSeconds -ge 4) {
                $w.due = $false
                $script:flashUntil[$id] = [DateTime]::Now.AddSeconds($flashSeconds)
                if ($cfg.sound) { [System.Media.SystemSounds]::Asterisk.Play() }
                $script:lastSig = $null   # force a rebuild so the row can flash
            }
        }
        if ($st -ne 'waiting') { foreach ($k in @($script:waitRounds.Keys)) { if ($k -like "$id|*") { $script:waitRounds[$k].since = $null } } }
        if ($st -ne 'idle') { $script:unread.Remove($id) }
        $script:prevStatus[$id] = $st
        $script:lastObj[$id] = $s
    }
    foreach ($id in @($script:prevStatus.Keys)) {
        if (-not $seen[$id]) {
            # Vanished while working or waiting: crashed or closed mid-turn, so keep a grey row for a moment.
            if ($script:prevStatus[$id] -in 'busy', 'waiting' -and $script:lastObj[$id]) {
                $g = $script:lastObj[$id].PSObject.Copy(); $g.status = 'gone'
                $script:ghosts[$id] = @{ s = $g; until = [DateTime]::Now.AddSeconds(8) }
            }
            $sid = if ($script:lastObj[$id]) { [string]$script:lastObj[$id].sessionId } else { '' }
            foreach ($t in $script:askCache, $script:busyCache, $script:subCache, $script:transcriptPath) { $t.Remove($sid) }
            foreach ($t in $script:prevStatus, $script:unread, $script:flashUntil, $script:lastObj, $script:rowNames) { $t.Remove($id) }
            foreach ($k in @($script:waitRounds.Keys)) { if ($k -like "$id|*") { $script:waitRounds.Remove($k) } }
        }
    }
    $script:scans++
    foreach ($id in @($script:ghosts.Keys)) { if ([DateTime]::Now -ge $script:ghosts[$id].until) { $script:ghosts.Remove($id) } }
}

$script:latest = @{}        # pid -> newest session object (tooltips read it when they open)
function Get-RowTip([int]$procId) {
    $s = $script:latest[$procId]
    if (-not $s) { $g = $script:ghosts[$procId]; if ($g) { $s = $g.s } }
    if (-not $s) { return '' }
    $st = [string]$s.status
    $meta = $states[$st]; if (-not $meta) { $meta = @{ label = $st } }
    $hideThis = Test-NameHidden $s
    $name = if ($hideThis) { $UiText.sessionN -f $s.idx } elseif ($s.name) { [string]$s.name } else { Split-Path $s.cwd -Leaf }
    $tip = $meta.label
    if ($st -eq 'waiting' -and $s.PSObject.Properties['waitingFor'] -and $s.waitingFor) { $tip = "$tip · $($s.waitingFor)" }
    if (-not $hideThis -and $s.PSObject.Properties['question'] -and $s.question) {
        $qText = [string]$s.question
        if ($qText.Length -gt 300) { $qText = $qText.Substring(0, 300) + '…' }
        $tip = "$tip`n$($UiText.askPrefix)$qText"
    }
    if ($script:unread[$procId]) { $tip = "$tip · $($UiText.unreadTip)" }
    if ($st -eq 'gone') { $tip = $UiText.goneTip }
    if ($st -eq 'busy') {
        if (-not $hideThis -and $s.PSObject.Properties['action'] -and $s.action) { $tip = "$tip`n$($s.action)" }
        $subs = if ($s.PSObject.Properties['subagents']) { [int]$s.subagents } else { 0 }
        if ($subs -gt 0) { $tip = "$tip`n$($UiText.subsTip -f $subs)" }
    }
    # The folder is shown only when the session runs somewhere other than the usual main folder.
    $dirLine = ''
    if ($s.cwd -and ([string]$s.cwd).TrimEnd('\', '/') -ne ([string]$cfg.mainDir).TrimEnd('\', '/')) { $dirLine = "`n$($s.cwd)" }
    if ($hideThis) { "$name`n$tip" } else { "$name`n$tip$dirLine" }
}

$script:rowNames = @{}      # pid -> session name
$script:noticeUntil = $null # a click result shown in the header for a few seconds
$script:lastSig = $null
function Update-View {
    $sessions = Get-Sessions
    Update-Transitions $sessions
    # Number by start order (stable when names are hidden), then show waiting sessions first.
    $k = 0; foreach ($s in $sessions) { $k++; $s | Add-Member -Force -NotePropertyName idx -NotePropertyValue $k }
    $script:latest = @{}; foreach ($s in $sessions) { $script:latest[[int]$s.pid] = $s }
    $script:liveNames = @($sessions | ForEach-Object { [string]$_.name } | Where-Object { $_ })
    $sessions = @(@($sessions | Where-Object { $_.status -eq 'waiting' }) + @($sessions | Where-Object { $_.status -ne 'waiting' }) +
                  @($script:ghosts.Values | ForEach-Object { $_.s }))
    # Skip the rebuild when nothing visible changed.
    $sig = (@($sessions | ForEach-Object {
        "$($_.pid)|$($_.status)|$($_.waitingFor)|$($_.name)|$($_.question)|$($_.subagents)|$($script:unread[[int]$_.pid])"
    }) -join ';') + "|$($cfg.hideNames)|$($cfg.compact)|$($cfg.hiddenSessions -join ',')"
    if ($sig -eq $script:lastSig) { return }
    $script:lastSig = $sig
    $rows.Children.Clear()
    $script:busyDots.Clear()
    $script:flashRows.Clear()
    $n = @{ busy = 0; waiting = 0; idle = 0 }
    $i = 0
    foreach ($s in $sessions) {
        $i++
        $st = [string]$s.status
        if ($n.ContainsKey($st)) { $n[$st]++ }
        $meta = $states[$st]; if (-not $meta) { $meta = @{ color = '#9CA3AF'; label = $st } }

        $row = New-Object System.Windows.Controls.StackPanel
        $row.Orientation = 'Horizontal'; $row.Margin = '0,2,0,2'

        $dot = New-Object System.Windows.Shapes.Ellipse
        $dot.Width = 11; $dot.Height = 11; $dot.Fill = Get-Brush $meta.color
        $dot.Margin = '0,0,8,0'; $dot.VerticalAlignment = 'Center'
        $glow = New-Object System.Windows.Media.Effects.DropShadowEffect
        $glow.Color = [Windows.Media.ColorConverter]::ConvertFromString($meta.color)
        $glow.BlurRadius = 8; $glow.ShadowDepth = 0; $glow.Opacity = 0.9
        if ($st -ne 'busy') { $dot.Effect = $glow }  # blur on an animated dot is costly on a transparent window
        if ($st -eq 'busy') { $dot.Opacity = Get-PulseOpacity; [void]$script:busyDots.Add($dot) }
        $row.Children.Add($dot) | Out-Null

        $unreadDot = $null
        if ($script:unread[[int]$s.pid]) {
            $unreadDot = New-Object System.Windows.Shapes.Ellipse
            $unreadDot.Width = 6; $unreadDot.Height = 6; $unreadDot.Fill = Get-Brush '#F87171'
            $unreadDot.VerticalAlignment = 'Center'; $unreadDot.Margin = '0,0,8,0'
        }
        if ($cfg.compact -and $unreadDot) { $row.Children.Add($unreadDot) | Out-Null }

        if ($st -ne 'gone') { $script:rowNames[[int]$s.pid] = [string]$s.name }   # real name for click-to-open, even when hidden
        $name = if (Test-NameHidden $s) { $UiText.sessionN -f $s.idx } elseif ($s.name) { [string]$s.name } else { Split-Path $s.cwd -Leaf }
        $subs = if ($s.PSObject.Properties['subagents']) { [int]$s.subagents } else { 0 }

        if (-not $cfg.compact) {
            $t = New-Object System.Windows.Controls.TextBlock
            $t.Text = $name; $t.Foreground = Get-Brush '#EEFFFFFF'; $t.FontSize = 12
            $t.FontFamily = 'Microsoft YaHei UI'; $t.MaxWidth = 200; $t.TextTrimming = 'CharacterEllipsis'
            $t.VerticalAlignment = 'Center'; $t.Margin = '0,0,10,0'
            $row.Children.Add($t) | Out-Null
            if ($unreadDot) { $row.Children.Add($unreadDot) | Out-Null }

            $a = New-Object System.Windows.Controls.TextBlock
            $a.Text = $meta.label   # no durations: the user wants the state only
            if ($st -eq 'busy' -and $subs -gt 0) { $a.Text = "$($meta.label) ×$subs" }
            $a.Foreground = Get-Brush $meta.color; $a.FontSize = 11; $a.FontFamily = 'Microsoft YaHei UI'
            $a.VerticalAlignment = 'Center'
            $row.Children.Add($a) | Out-Null
        }
        if (-not $cfg.hideNames -and $st -ne 'gone') {
            $rowEye = New-Object System.Windows.Controls.Grid
            $rowEye.Width = 13; $rowEye.Height = 13; $rowEye.Margin = '8,0,0,0'; $rowEye.VerticalAlignment = 'Center'
            $rowEye.Background = [System.Windows.Media.Brushes]::Transparent; $rowEye.Cursor = 'Hand'; $rowEye.Visibility = 'Hidden'
            $rowEye.ToolTip = $UiText.rowEyeTip; $rowEye.Tag = Get-SessionKey $s
            $eyePath = New-Object System.Windows.Shapes.Path
            $eyePath.Data = [System.Windows.Media.Geometry]::Parse('M1,6.5 C3,3 10,3 12,6.5 C10,10 3,10 1,6.5 Z')
            $eyePath.Stroke = Get-Brush '#99FFFFFF'; $eyePath.StrokeThickness = 1.1
            $pupil = New-Object System.Windows.Shapes.Ellipse; $pupil.Width = 3.6; $pupil.Height = 3.6; $pupil.Fill = Get-Brush '#99FFFFFF'
            [void]$rowEye.Children.Add($eyePath); [void]$rowEye.Children.Add($pupil)
            if ($cfg.hiddenSessions -contains $rowEye.Tag) {
                $slash = New-Object System.Windows.Shapes.Line
                $slash.X1 = 2; $slash.Y1 = 11; $slash.X2 = 11; $slash.Y2 = 2; $slash.Stroke = Get-Brush '#99FFFFFF'; $slash.StrokeThickness = 1.3
                [void]$rowEye.Children.Add($slash)
            }
            $rowEye.Add_MouseLeftButtonUp({ param($sender, $e)
                $k = [string]$sender.Tag
                $cfg.hiddenSessions = if ($cfg.hiddenSessions -contains $k) { @($cfg.hiddenSessions | Where-Object { $_ -ne $k }) } else { @($cfg.hiddenSessions) + $k }
                $e.Handled = $true; Save-Cfg; Update-View
            })
            [void]$row.Children.Add($rowEye)
        }
        # Wrapped in a Border so the row can flash; Tag carries the pid for click handling.
        $cell = New-Object System.Windows.Controls.Border
        $cell.CornerRadius = 4; $cell.Padding = '4,1,4,1'; $cell.Margin = '-4,0,-4,0'
        $cell.Background = [System.Windows.Media.Brushes]::Transparent; $cell.Tag = [int]$s.pid
        $cell.Child = $row
        $cell.ToolTip = ' '   # placeholder; filled when it opens
        $cell.Add_ToolTipOpening({ param($sender, $e) $sender.ToolTip = Get-RowTip ([int]$sender.Tag) })
        # The row's own eye button only shows while the row is hovered.
        $cell.Add_MouseEnter({ param($sender, $e) foreach ($x in $sender.Child.Children) { if ($x -is [System.Windows.Controls.Grid]) { $x.Visibility = 'Visible' } } })
        $cell.Add_MouseLeave({ param($sender, $e) foreach ($x in $sender.Child.Children) { if ($x -is [System.Windows.Controls.Grid]) { $x.Visibility = 'Hidden' } } })
        if ($script:flashUntil.ContainsKey([int]$s.pid)) { [void]$script:flashRows.Add($cell) }
        $rows.Children.Add($cell) | Out-Null
    }
    if ($i -eq 0) {
        $empty = New-Object System.Windows.Controls.TextBlock
        $empty.Text = $UiText.empty; $empty.Foreground = Get-Brush '#88FFFFFF'; $empty.FontSize = 11
        $empty.FontFamily = 'Microsoft YaHei UI'
        $rows.Children.Add($empty) | Out-Null
    }
    $summary.Text = if ($cfg.compact) { 'Claude' } else { $UiText.summary -f $n.busy, $n.waiting, $n.idle }
    Update-Tray $n ($n.busy + $n.waiting + $n.idle)
    $eyeSlash.Visibility = if ($cfg.hideNames) { 'Visible' } else { 'Collapsed' }
}

# Drag anywhere to move; position is remembered.
$win.Add_MouseLeftButtonDown({ param($sender, $e)
    if ($eye.IsMouseOver -or $closeBtn.IsMouseOver) { return }
    foreach ($c in @($rows.Children)) {
        if ($c.Tag -and $c.IsMouseOver) { foreach ($x in $c.Child.Children) { if ($x -is [System.Windows.Controls.Grid] -and $x.IsMouseOver) { return } } }
    }
    $before = "$([int]$win.Left),$([int]$win.Top)"
    try { $win.DragMove() } catch {}
    if ("$([int]$win.Left),$([int]$win.Top)" -ne $before) { $cfg.left = [int]$win.Left; $cfg.top = [int]$win.Top; Save-Cfg; return }
    # A click without moving opens that session in Claude and clears its unread dot.
    $procId = 0
    foreach ($c in @($rows.Children)) { if ($c.Tag -and $c.IsMouseOver) { $procId = [int]$c.Tag; break } }
    if (-not $procId) { return }
    if ($script:unread.ContainsKey($procId)) { $script:unread.Remove($procId); Update-View }
    $msg = $null
    try { $msg = Open-ClaudeSession $script:rowNames[$procId] } catch { $msg = $UiText.openFailed }
    if ($msg) { $script:noticeText = $msg; $summary.Text = $msg; $script:noticeUntil = [DateTime]::Now.AddSeconds(3) }
})
$eye.Add_MouseLeftButtonUp({ $cfg.hideNames = -not $cfg.hideNames; Save-Cfg; Update-View })
$closeBtn.Add_MouseLeftButtonUp({ Hide-Lights })

# Right-click menu: hide names, compact (lights only), exit.
$menu = New-Object System.Windows.Controls.ContextMenu
$miRow = New-Object System.Windows.Controls.MenuItem   # per-row: hide/show just this session's name
$miRowSep = New-Object System.Windows.Controls.Separator
$script:menuRowKey = $null
$miHide = New-Object System.Windows.Controls.MenuItem; $miHide.Header = $UiText.hideAll; $miHide.IsCheckable = $true
$miCompact = New-Object System.Windows.Controls.MenuItem; $miCompact.Header = $UiText.compact; $miCompact.IsCheckable = $true
$miSound = New-Object System.Windows.Controls.MenuItem; $miSound.Header = $UiText.sound; $miSound.IsCheckable = $true
$miExit = New-Object System.Windows.Controls.MenuItem; $miExit.Header = $UiText.exit
$menu.Items.Add($miRow) | Out-Null; $menu.Items.Add($miRowSep) | Out-Null
$menu.Items.Add($miHide) | Out-Null; $menu.Items.Add($miCompact) | Out-Null; $menu.Items.Add($miSound) | Out-Null
$menu.Items.Add((New-Object System.Windows.Controls.Separator)) | Out-Null; $menu.Items.Add($miExit) | Out-Null
# Which row was right-clicked? Read it before the menu opens: once open, the menu captures the mouse.
$win.Add_ContextMenuOpening({
    $script:menuRowKey = $null
    foreach ($c in @($rows.Children)) {
        if ($c.Tag -and $c.IsMouseOver -and $script:latest[[int]$c.Tag]) { $script:menuRowKey = Get-SessionKey $script:latest[[int]$c.Tag] }
    }
})
$menu.Add_Opened({
    $miHide.IsChecked = [bool]$cfg.hideNames; $miCompact.IsChecked = [bool]$cfg.compact; $miSound.IsChecked = [bool]$cfg.sound
    $show = [bool]$script:menuRowKey -and -not $cfg.hideNames
    $miRow.Visibility = if ($show) { 'Visible' } else { 'Collapsed' }; $miRowSep.Visibility = $miRow.Visibility
    if ($show) { $miRow.Header = if ($cfg.hiddenSessions -contains $script:menuRowKey) { $UiText.showRowName } else { $UiText.hideRowName } }
})
$miRow.Add_Click({
    $k = $script:menuRowKey; if (-not $k) { return }
    $cfg.hiddenSessions = if ($cfg.hiddenSessions -contains $k) { @($cfg.hiddenSessions | Where-Object { $_ -ne $k }) } else { @($cfg.hiddenSessions) + $k }
    Save-Cfg; Update-View
})
$miSound.Add_Click({ $cfg.sound = $miSound.IsChecked; Save-Cfg })
$miHide.Add_Click({ $cfg.hideNames = $miHide.IsChecked; Save-Cfg; Update-View })
$miCompact.Add_Click({ $cfg.compact = $miCompact.IsChecked; Save-Cfg; Update-View })
$miExit.Add_Click({ Exit-Lights })
$win.ContextMenu = $menu

# --- Tray icon: shows the most urgent state (waiting > busy > idle); ✕ hides the window here ---------
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
# Icons of killed processes stay in the tray until the mouse passes over them. A mouse-move sweep over
# the tray toolbars makes Explorer notice and drop them. It only sends moves, never clicks.
Add-Type -Namespace SessionLights -Name Tray -MemberDefinition @'
[DllImport("user32.dll")] static extern IntPtr FindWindow(string c, string w);
[DllImport("user32.dll")] static extern IntPtr FindWindowEx(IntPtr p, IntPtr a, string c, string w);
[DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint flags, uint ms, out IntPtr res);
public struct RECT { public int Left, Top, Right, Bottom; }
static void Sweep(IntPtr tb) {
    RECT r; IntPtr res; if (tb == IntPtr.Zero || !GetClientRect(tb, out r)) return;
    for (int x = 0; x < r.Right; x += 4) for (int y = 0; y < r.Bottom; y += 4)   // WM_MOUSEMOVE, SMTO_ABORTIFHUNG
        if (SendMessageTimeout(tb, 0x0200, IntPtr.Zero, (IntPtr)((y << 16) | (x & 0xFFFF)), 2, 50, out res) == IntPtr.Zero) return;
}
public static IntPtr[] Toolbars() {
    IntPtr tray = FindWindow("Shell_TrayWnd", null);
    IntPtr notify = FindWindowEx(tray, IntPtr.Zero, "TrayNotifyWnd", null);
    IntPtr pager = FindWindowEx(notify, IntPtr.Zero, "SysPager", null);
    IntPtr overflow = FindWindow("NotifyIconOverflowWindow", null);
    return new IntPtr[] { FindWindowEx(pager, IntPtr.Zero, "ToolbarWindow32", null),
                          FindWindowEx(overflow, IntPtr.Zero, "ToolbarWindow32", null) };
}
public static void Clean() { foreach (IntPtr tb in Toolbars()) Sweep(tb); }
'@
try { [SessionLights.Tray]::Clean() } catch {}

$tray = New-Object System.Windows.Forms.NotifyIcon
$script:trayIcons = @{}
function Get-DotIcon([string]$hex) {
    if (-not $script:trayIcons[$hex]) {
        $bmp = New-Object System.Drawing.Bitmap 16, 16
        $g = [System.Drawing.Graphics]::FromImage($bmp); $g.SmoothingMode = 'AntiAlias'
        $g.FillEllipse((New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml($hex))), 2, 2, 12, 12)
        $g.DrawEllipse((New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(140, 0, 0, 0)), 1), 2, 2, 12, 12)
        $script:trayIcons[$hex] = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
    }
    $script:trayIcons[$hex]
}
$script:trayColor = $null
function Update-Tray($n, [int]$total) {
    $hex = if ($n.waiting -gt 0) { $states.waiting.color } elseif ($n.busy -gt 0) { $states.busy.color } elseif ($total -gt 0) { $states.idle.color } else { '#9CA3AF' }
    if ($hex -ne $script:trayColor) { $tray.Icon = Get-DotIcon $hex; $script:trayColor = $hex }
    $tray.Text = $UiText.summary -f $n.busy, $n.waiting, $n.idle   # NotifyIcon caps this at 63 chars
}

function Show-Lights { $win.Show(); $win.Activate() | Out-Null; $pulseTimer.Start(); $cfg.hidden = $false; Save-Cfg }
function Hide-Lights { $win.Hide(); $pulseTimer.Stop(); $cfg.hidden = $true; Save-Cfg }
function Exit-Lights {
    $script:exiting = $true
    $timer.Stop(); $pulseTimer.Stop()
    $tray.Visible = $false; $tray.Dispose()
    $mutex.ReleaseMutex()
    $app.Shutdown()
}

$trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
$tmToggle = $trayMenu.Items.Add($UiText.showWindow)
$tmHide = $trayMenu.Items.Add($UiText.hideNames)
$tmSound = $trayMenu.Items.Add($UiText.sound)
[void]$trayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
$tmExit = $trayMenu.Items.Add($UiText.exit)
$trayMenu.Add_Opening({
    $tmToggle.Text = if ($win.IsVisible) { $UiText.toTray } else { $UiText.showWindow }
    $tmHide.Checked = [bool]$cfg.hideNames; $tmSound.Checked = [bool]$cfg.sound
})
$tmToggle.Add_Click({ if ($win.IsVisible) { Hide-Lights } else { Show-Lights } })
$tmHide.Add_Click({ $cfg.hideNames = -not $cfg.hideNames; Save-Cfg; Update-View })
$tmSound.Add_Click({ $cfg.sound = -not $cfg.sound; Save-Cfg })
$tmExit.Add_Click({ Exit-Lights })
$tray.ContextMenuStrip = $trayMenu
$tray.Add_MouseClick({ param($s, $e) if ($e.Button -eq 'Left') { if ($win.IsVisible) { Hide-Lights } else { Show-Lights } } })
$tray.Icon = Get-DotIcon '#9CA3AF'; $tray.Text = 'Claude'
$tray.Visible = $true

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(2)   # alerts wait 4s anyway; 2s halves the polling cost
# Follows Claude: close after Claude has been gone for a minute (started again by the SessionStart hook).
$script:claudeGoneSince = $null
$script:tick = 0
$timer.Add_Tick({
    if ($quitEvent.WaitOne(0)) { Exit-Lights; return }
    try { Update-View } catch {}
    if ($script:noticeUntil) {
        if ([DateTime]::Now -ge $script:noticeUntil) { $script:noticeUntil = $null; $script:lastSig = $null }
        else { $summary.Text = $script:noticeText }
    }
    $script:tick++
    # Every minute: compact the heap (incl. large strings from transcript reads) and hand free memory back.
    if ($script:tick % 30 -eq 0) {
        [System.Runtime.GCSettings]::LargeObjectHeapCompactionMode = 'CompactOnce'
        [GC]::Collect(); [GC]::WaitForPendingFinalizers(); [GC]::Collect()
        try { [void][SessionLights.Mem]::SetProcessWorkingSetSize([SessionLights.Mem]::GetCurrentProcess(), [IntPtr](-1), [IntPtr](-1)) } catch {}
        foreach ($k in @($script:aliveCache.Keys)) { if (([DateTime]::Now - $script:aliveCache[$k].at).TotalSeconds -gt 60) { $script:aliveCache.Remove($k) } }
    }
    # Process lookups are slow: every ~16s normally, every tick once Claude has gone.
    if ($script:tick % 8 -ne 0 -and -not $script:claudeGoneSince) { return }
    if (Get-Process -Name 'claude' -ErrorAction SilentlyContinue) { $script:claudeGoneSince = $null }
    elseif (-not $script:claudeGoneSince) { $script:claudeGoneSince = [DateTime]::Now }
    elseif (([DateTime]::Now - $script:claudeGoneSince).TotalSeconds -ge 60) { Exit-Lights }
})
$pulseTimer = New-Object System.Windows.Threading.DispatcherTimer
$pulseTimer.Interval = [TimeSpan]::FromMilliseconds(125)
$rootBorder = $win.FindName('Root')
$flashBase = [Windows.Media.ColorConverter]::ConvertFromString('#F59E0B')
$pulseTimer.Add_Tick({
    $o = Get-PulseOpacity; foreach ($d in $script:busyDots) { $d.Opacity = $o }
    # Flash newly waiting rows (and the window border) three times, then settle.
    $now = [DateTime]::Now; $any = $false
    foreach ($cell in @($script:flashRows)) {
        $until = $script:flashUntil[[int]$cell.Tag]
        if (-not $until -or $now -ge $until) {
            $cell.Background = [System.Windows.Media.Brushes]::Transparent
            $script:flashRows.Remove($cell); $script:flashUntil.Remove([int]$cell.Tag); continue
        }
        $any = $true
        $phase = ($flashSeconds - ($until - $now).TotalSeconds) / 0.8 * 2 * [math]::PI
        $alpha = [byte](110 * (0.5 - 0.5 * [math]::Cos($phase)))
        $cell.Background = New-Object System.Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromArgb($alpha, $flashBase.R, $flashBase.G, $flashBase.B))
    }
    if ($any -ne $script:borderFlashing) {   # repaint the border only when the flash starts or ends
        $script:borderFlashing = $any
        $rootBorder.BorderBrush = if ($any) { New-Object System.Windows.Media.SolidColorBrush $flashBase } else { Get-Brush '#33FFFFFF' }
    }
})
$script:borderFlashing = $false
# Alt+F4 or a system close hides to the tray too; only Exit-Lights really quits.
$script:exiting = $false
$win.Add_Closing({ param($s, $e) if (-not $script:exiting) { $e.Cancel = $true; Hide-Lights } })

# Explicit shutdown so the app keeps running (tray only) while the window is hidden.
[System.Windows.Media.RenderOptions]::ProcessRenderMode = 'SoftwareOnly'   # tiny window; saves ~20MB vs. hardware rendering
$app = New-Object System.Windows.Application
$app.ShutdownMode = 'OnExplicitShutdown'
Update-View; $timer.Start()
if (-not $cfg.hidden) { $win.Show(); $pulseTimer.Start() }
$app.Run() | Out-Null
