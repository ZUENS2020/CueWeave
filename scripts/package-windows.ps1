$ErrorActionPreference = "Stop"
$Repo = Split-Path -Parent $PSScriptRoot
$Cargo = Join-Path $env:USERPROFILE ".rustup\toolchains\stable-x86_64-pc-windows-msvc\bin\cargo.exe"
if (-not (Test-Path $Cargo)) { $Cargo = "cargo" }

Set-Location $Repo
& $Cargo test --workspace --all-targets
if ($LASTEXITCODE -ne 0) { throw "cargo test failed" }

& $Cargo build --locked --release -p cueweave-cli
if ($LASTEXITCODE -ne 0) { throw "cargo build failed" }

dotnet build "$Repo\apps\windows\CueWeave.Windows.Tests\CueWeave.Windows.Tests.csproj" --nologo
if ($LASTEXITCODE -ne 0) { throw "dotnet test build failed" }
$TestExe = Join-Path $Repo "apps\windows\CueWeave.Windows.Tests\bin\Debug\net10.0\CueWeave.Windows.Tests.exe"
& $TestExe
if ($LASTEXITCODE -ne 0) { throw "dotnet test failed" }

dotnet publish "$Repo\apps\windows\CueWeave.Windows\CueWeave.Windows.csproj" -c Release -r win-x64 --self-contained -p:Platform=x64
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed" }

$Publish = Join-Path $Repo "apps\windows\CueWeave.Windows\bin\Release\net10.0-windows10.0.26100.0\win-x64\publish"
if (-not (Test-Path $Publish)) {
    $Publish = Join-Path $Repo "apps\windows\CueWeave.Windows\bin\x64\Release\net10.0-windows10.0.26100.0\win-x64\publish"
}
$Cli = Join-Path $Repo "target\release\cueweave-cli.exe"
if (Test-Path $Cli) { Copy-Item $Cli $Publish -Force }
Write-Output $Publish
