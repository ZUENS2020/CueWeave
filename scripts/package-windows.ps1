$ErrorActionPreference = "Stop"
$Repo = Split-Path -Parent $PSScriptRoot
$ToolchainRoot = Join-Path $env:USERPROFILE ".rustup\toolchains"
$Toolchain = $null
foreach ($name in @("1.98.0-x86_64-pc-windows-msvc", "stable-x86_64-pc-windows-msvc")) {
    $candidate = Join-Path $ToolchainRoot "$name\bin"
    if (Test-Path (Join-Path $candidate "cargo.exe")) { $Toolchain = $candidate; break }
}
$Cargo = if ($Toolchain) { Join-Path $Toolchain "cargo.exe" } else { "cargo" }
if ($Toolchain) {
    $env:RUSTC = Join-Path $Toolchain "rustc.exe"
    $env:CARGO = $Cargo
}

# SSH/network logons cannot traverse .cargo\bin rustup shims (WinError 448).
$dotnetCmd = Get-Command dotnet -ErrorAction SilentlyContinue
$dotnetDir = if ($dotnetCmd) { Split-Path $dotnetCmd.Source } else { Join-Path ${env:ProgramFiles} "dotnet" }
$env:Path = @(
    $Toolchain
    $dotnetDir
    "C:\Windows\System32"
    "C:\Windows"
    "C:\Windows\System32\WindowsPowerShell\v1.0"
) -join ";"

Set-Location $Repo
& $Cargo test --locked --workspace --all-targets
if ($LASTEXITCODE -ne 0) { throw "cargo test failed" }

& $Cargo build --locked --release -p cueweave-cli
if ($LASTEXITCODE -ne 0) { throw "cargo build failed" }

$AppProj = Join-Path $Repo "apps\windows\CueWeave.Windows\CueWeave.Windows.csproj"
$TestProj = Join-Path $Repo "apps\windows\CueWeave.Windows.Tests\CueWeave.Windows.Tests.csproj"
$AppRoot = Join-Path $Repo "apps\windows\CueWeave.Windows"
foreach ($stale in @("bin", "obj")) {
    $path = Join-Path $AppRoot $stale
    if (Test-Path $path) { Remove-Item $path -Recurse -Force }
}
$RestoreLock = if ($env:CI -eq "true") { "--locked-mode" } else { "--use-lock-file" }
dotnet restore $AppProj -r win-x64 $RestoreLock --nologo
if ($LASTEXITCODE -ne 0) { throw "dotnet restore app failed" }
dotnet restore $TestProj $RestoreLock --nologo
if ($LASTEXITCODE -ne 0) { throw "dotnet restore tests failed" }

dotnet build $TestProj --nologo --no-restore
if ($LASTEXITCODE -ne 0) { throw "dotnet test build failed" }
$TestExe = Join-Path $Repo "apps\windows\CueWeave.Windows.Tests\bin\Debug\net10.0\CueWeave.Windows.Tests.exe"
& $TestExe
if ($LASTEXITCODE -ne 0) { throw "dotnet test failed" }

dotnet publish $AppProj -c Release -r win-x64 --self-contained --no-restore -p:Platform=x64 -p:WindowsAppSDKSelfContained=true -p:WindowsPackageType=None -p:PublishTrimmed=false -p:PublishReadyToRun=false -p:PublishSingleFile=false -p:CopyOutputSymbolsToPublishDirectory=false
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed" }

$Publish = Join-Path $Repo "apps\windows\CueWeave.Windows\bin\Release\net10.0-windows10.0.26100.0\win-x64\publish"
if (-not (Test-Path $Publish)) {
    $Publish = Join-Path $Repo "apps\windows\CueWeave.Windows\bin\x64\Release\net10.0-windows10.0.26100.0\win-x64\publish"
}
$Cli = Join-Path $Repo "target\release\cueweave-cli.exe"
if (Test-Path $Cli) { Copy-Item $Cli $Publish -Force }
$Dist = Join-Path $Repo "dist\CueWeave-windows-x64"
New-Item -ItemType Directory -Force -Path $Dist | Out-Null
Get-ChildItem $Dist -Force | Remove-Item -Recurse -Force
Copy-Item (Join-Path $Publish "*") $Dist -Recurse -Force
Get-ChildItem $Dist -Recurse -File -Include *.pdb, boot.log | Remove-Item -Force
$PortableReadme = Join-Path $PSScriptRoot "windows-portable-readme.txt"
if (Test-Path $PortableReadme) { Copy-Item $PortableReadme (Join-Path $Dist "README.txt") -Force }
$ZipDir = Join-Path $Repo "dist\_windows-zip"
$Inner = Join-Path $ZipDir "CueWeave"
if (Test-Path $ZipDir) { Remove-Item $ZipDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $Inner | Out-Null
Copy-Item (Join-Path $Dist "*") $Inner -Recurse -Force
$Zip = Join-Path $Repo "dist\CueWeave-windows-x64.zip"
if (Test-Path $Zip) { Remove-Item $Zip -Force }
Push-Location $ZipDir
# tar.exe writes ZIP spec forward slashes; Compress-Archive uses backslashes.
tar.exe -a -c -f $Zip CueWeave
Pop-Location
Remove-Item $ZipDir -Recurse -Force
Write-Output $Publish
Write-Output $Zip
