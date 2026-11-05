# 用 mock CLI 验证 agentflow-runner 的进程生命周期：
# 父进程退出后继续运行、陈旧 token 拒绝、取消结束进程树、非零退出、无效输出和双流大日志。
param(
    [string]$Runner = "target\debug\agentflow-runner.exe",
    [string]$Mock = "target\debug\agentflow-mock-cli.exe"
)

$ErrorActionPreference = "Stop"
$runnerPath = (Resolve-Path $Runner).Path
$mockPath = (Resolve-Path $Mock).Path
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("agentflow-runner-test-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $testRoot | Out-Null

function Fail([string]$message) {
    Write-Error $message
    exit 1
}

function Write-Utf8([string]$path, [string]$text) {
    [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding $false))
}

function New-Launch([string]$name, [string[]]$arguments, [int]$timeout) {
    $caseRoot = Join-Path $testRoot $name
    New-Item -ItemType Directory -Path (Join-Path $caseRoot "control") -Force | Out-Null
    $attempt = [guid]::NewGuid().ToString()
    $token = [guid]::NewGuid().ToString()
    $launch = [ordered]@{
        schemaVersion            = 1
        attemptId                = $attempt
        executionToken           = $token
        executablePath           = $mockPath
        arguments                = $arguments
        workingDirectory         = $caseRoot
        environment              = @{ PATH = "$env:SystemRoot\System32;$env:SystemRoot"; SystemRoot = $env:SystemRoot }
        stdoutPath               = Join-Path $caseRoot "stdout.log"
        stderrPath               = Join-Path $caseRoot "stderr.log"
        identityPath             = Join-Path $caseRoot "identity.json"
        heartbeatPath            = Join-Path $caseRoot "heartbeat.json"
        cancellationPath         = Join-Path $caseRoot "control\cancel.json"
        resultPath               = Join-Path $caseRoot "result.json"
        timeoutSeconds           = $timeout
        cancellationGraceSeconds = 1
    }
    $launchPath = Join-Path $caseRoot "launch.json"
    Write-Utf8 $launchPath ($launch | ConvertTo-Json -Depth 4)
    return [pscustomobject]@{ Root = $caseRoot; Launch = $launchPath; Attempt = $attempt; Token = $token }
}

function Write-Cancel($case, [string]$token) {
    $request = @{ schemaVersion = 1; attemptId = $case.Attempt; executionToken = $token } | ConvertTo-Json -Compress
    Write-Utf8 (Join-Path $case.Root "control\cancel.json") $request
}

function Wait-File([string]$path, [int]$seconds = 10) {
    $deadline = (Get-Date).AddSeconds($seconds)
    while (-not (Test-Path $path) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 100 }
    return (Test-Path $path)
}

function Read-Result($case) { Get-Content (Join-Path $case.Root "result.json") -Raw | ConvertFrom-Json }

function Start-Runner($case) {
    Start-Process -FilePath $runnerPath -ArgumentList "--launch", "`"$($case.Launch)`"" -WindowStyle Hidden -PassThru
}

try {
    # 1. runner 独立运行：启动它的 PowerShell 进程不等待，结果照常写出
    $survival = New-Launch "survival" @("delay", "1000") 10
    Start-Runner $survival | Out-Null
    if (-not (Wait-File (Join-Path $survival.Root "result.json"))) { Fail "survival: result.json was not written" }
    if ((Read-Result $survival).terminationReason -ne "exited") { Fail "survival: unexpected termination reason" }
    if (-not (Select-String -Path (Join-Path $survival.Root "stdout.log") -Pattern '"delayed":true' -Quiet)) { Fail "survival: missing delayed output" }

    # 2. 取消：陈旧 token 被拒绝，正确 token 结束包含派生子进程的进程树
    $cancel = New-Launch "cancel" @("derived-child") 60
    Start-Runner $cancel | Out-Null
    if (-not (Wait-File (Join-Path $cancel.Root "identity.json"))) { Fail "cancel: identity.json was not written" }
    Write-Cancel $cancel "stale-token"
    Start-Sleep -Milliseconds 800
    if (Test-Path (Join-Path $cancel.Root "result.json")) { Fail "cancel: runner accepted a stale cancellation token" }
    Write-Cancel $cancel $cancel.Token
    if (-not (Wait-File (Join-Path $cancel.Root "result.json"))) { Fail "cancel: result.json was not written" }
    if ((Read-Result $cancel).terminationReason -ne "cancelled") { Fail "cancel: unexpected termination reason" }
    $identity = Get-Content (Join-Path $cancel.Root "identity.json") -Raw | ConvertFrom-Json
    $derived = (Get-Content (Join-Path $cancel.Root "stdout.log") -TotalCount 1 | ConvertFrom-Json).childPID
    Start-Sleep -Milliseconds 300
    if (Get-Process -Id $identity.childPid -ErrorAction SilentlyContinue) { Fail "cancel: agent process is still running" }
    if (Get-Process -Id $derived -ErrorAction SilentlyContinue) { Fail "cancel: derived child process is still running" }

    # 3. 非零退出码
    $failure = New-Launch "failure" @("failure") 10
    & $runnerPath --launch $failure.Launch | Out-Null
    if ((Read-Result $failure).exitCode -ne 42) { Fail "failure: expected exit code 42" }
    if (-not (Select-String -Path (Join-Path $failure.Root "stderr.log") -Pattern "intentional mock failure" -Quiet)) { Fail "failure: missing stderr" }

    # 4. 无效输出照常记录，由调度器判定为 invalid_output
    $invalid = New-Launch "invalid" @("invalid-json") 10
    & $runnerPath --launch $invalid.Launch | Out-Null
    if (-not (Select-String -Path (Join-Path $invalid.Root "stdout.log") -Pattern "this is intentionally not JSON" -Quiet)) { Fail "invalid: missing stdout" }

    # 5. stdout / stderr 同时超过 500 KB 不死锁
    $log = New-Launch "long-log" @("long-log", "10000") 20
    & $runnerPath --launch $log.Launch | Out-Null
    if ((Get-Item (Join-Path $log.Root "stdout.log")).Length -le 500000) { Fail "long-log: stdout too small" }
    if ((Get-Item (Join-Path $log.Root "stderr.log")).Length -le 500000) { Fail "long-log: stderr too small" }

    Write-Output "runner survival, cancellation, failure, invalid output, and long-log checks passed"
}
finally {
    Remove-Item -Recurse -Force $testRoot -ErrorAction SilentlyContinue
}
