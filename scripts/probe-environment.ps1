# 输出本机构建环境与 Agent CLI 探测结果，用法：
#   powershell -File scripts\probe-environment.ps1 codex agy
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Cli = @())

$os = Get-CimInstance Win32_OperatingSystem
"os_product_name=$($os.Caption)"
"os_version=$($os.Version)"
"os_build=$($os.BuildNumber)"
"architecture=$env:PROCESSOR_ARCHITECTURE"

function Probe([string]$name, [scriptblock]$command) {
    try { "$name=$((& $command) | Select-Object -First 1)" } catch { "$name=unavailable" }
}
Probe "rust_version" { rustc --version }
Probe "cargo_version" { cargo --version }
Probe "rust_host" { rustc --print host-tuple }
Probe "node_version" { node --version }
Probe "npm_version" { npm --version }
Probe "git_version" { git --version }
if (Test-Path ".\node_modules\.bin\tauri.cmd") {
    Probe "tauri_cli_version" { & .\node_modules\.bin\tauri.cmd --version }
} else {
    "tauri_cli_version=unavailable"
}

foreach ($name in $Cli) {
    $found = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $found) {
        "cli.$name=not_found"
        continue
    }
    "cli.$name.path=$($found.Source)"
    # 部分 CLI 不支持 --version 且不会自动退出，最多等待 10 秒
    $out = [IO.Path]::GetTempFileName()
    $process = Start-Process -FilePath $found.Source -ArgumentList "--version" -NoNewWindow -PassThru `
        -RedirectStandardOutput $out -RedirectStandardError "$out.err"
    if ($process.WaitForExit(10000)) {
        $version = Get-Content $out -TotalCount 1
        if (-not $version) { $version = "unavailable" }
        "cli.$name.version=$version"
    } else {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        "cli.$name.version=unavailable"
    }
    Remove-Item $out, "$out.err" -ErrorAction SilentlyContinue
}
