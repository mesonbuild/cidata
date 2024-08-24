param (
  [string]$Arch     = "x64",
  [string]$Compiler = $null,
  [bool]$Boost      = $false,
  [bool]$DMD        = $false
)

echo ""
echo "=== BEGIN INSTALL ==="

$ScriptDir = Split-Path $script:MyInvocation.MyCommand.Path

# Add downloaded files to path
$env:Path = "$ScriptDir;$env:Path"

# Install installers
echo " - Installing msi packages"
Start-Process msiexec.exe -ArgumentList '/i msmpisdk.msi /quiet' -Wait
Start-Process $ScriptDir\MSMpiSetup.exe -ArgumentList '-unattend -full' -Wait

# import ms-mpi env vars (set by installer)
foreach ($p in "MSMPI_INC", "MSMPI_LIB32", "MSMPI_LIB64") {
  $v = [Environment]::GetEnvironmentVariable($p, "Machine")
  Set-Content "env:$p" "$v"
}

if ($Boost) {
  $env:BOOST_ROOT = $env:BOOST_ROOT_@BOOST_FILENAME@

  echo " - Using preinstalled boost version: $env:BOOST_ROOT"

  $env:Path = "$env:BOOST_ROOT\lib;$env:Path"

  # if ($Arch -eq "x64") { $BoostBitness = "64" } else { $BoostBitness = "32" }
  # echo " - Installing $BoostBitness bit boost"
  # Start-Process $ScriptDir\boost$BoostBitness.exe -ArgumentList "/dir=$env:AGENT_WORKFOLDER\boost_@BOOST_FILENAME@ /silent" -Wait
  # $env:BOOST_ROOT = "$env:AGENT_WORKFOLDER\boost_@BOOST_FILENAME@"
  # $env:Path       = "$env:Path;$env:BOOST_ROOT\lib$BoostBitness-msvc-@BOOST_ABI_TAG@"
}

if ($DMD) {
  echo " - Installing DMD"
  if ($Arch -eq "x64") {
    $dmd_bin = Join-Path $ScriptDir "dmd2\windows\bin64"
    $dmdArch = "x86_64"
  } else {
    $dmd_bin = Join-Path $ScriptDir "dmd2\windows\bin"
    $dmdArch = "x86"
  }
  $env:Path = $env:Path + ";" + $dmd_bin

  & dmd.exe --version

  # The --arch switch is required, see: https://github.com/dlang/dub/pull/2962
  & dub fetch urld@3.0.0
  & dub build urld --compiler=dmd --arch=$dmdArch
  & dub fetch dubtestproject@1.2.0
  & dub build dubtestproject:test1 --compiler=dmd --arch=$dmdArch
  & dub build dubtestproject:test2 --compiler=dmd --arch=$dmdArch
  & dub build dubtestproject:test3 --compiler=dmd --arch=$dmdArch
}

echo " - Importing the correct vcvarsall.bat"

# test_find_program exercises some behaviour which relies on .py being in PATHEXT
$env:PATHEXT += ';.py'

$origPath = $env:Path
# import visual studio variables
if ($Compiler -eq 'msvc2019') {
  $vcvars = "C:\Program Files (x86)\Microsoft Visual Studio\2019\Enterprise\VC\Auxiliary\Build\vcvarsall.bat"
} else {
  # Note: this is also for clangcl
  $vcvars = "C:\Program Files (x86)\Microsoft Visual Studio\2017\Enterprise\VC\Auxiliary\Build\vcvarsall.bat"
}

## A multiline commit message containing "=" can interact badly with this
## hack to extract the environment from vcvarsall.bat
Remove-Item env:BUILD_SOURCEVERSIONMESSAGE

# arch for the vcvars script includes the host when cross-compiling
$vcarch = $env:arch
if ($env:arch -eq 'arm64') {
  $vcarch = "amd64_arm64"
}

## ask cmd.exe to output the environment table after the batch file completes
$tempFile = [IO.Path]::GetTempFileName()
cmd /c " `"$vcvars`" $vcarch && set > `"$tempFile`" "

## go through the environment variables in the temp file.
## for each of them, set the variable in our local environment.
Get-Content $tempFile | Foreach-Object {
  if($_ -match "^(.*?)=(.*)$") {
    Set-Content "env:\$($matches[1])" $matches[2]
  }
}
Remove-Item $tempFile

if ($Compiler -eq 'clang-cl') {
  echo " - Installing LLVM"
  # drop visual studio from PATH
  # (but leave INCLUDE, LIB and WindowsSdkDir environment variables set)
  $env:Path = $origPath

  # install llvm for clang-cl builds
  Start-Process $ScriptDir\LLVM.exe -ArgumentList '/S' -Wait
  $env:Path = "C:\Program Files\LLVM\bin;$env:Path"
  $env:CC   = "clang-cl"
  $env:CXX  = "clang-cl"

  # and use Windows SDK tools
  $env:Path = "$env:WindowsSdkDir\bin\$Arch;$env:Path"
}

# add .NET framework tools to path for resgen for C# tests
# (always use 32-bit tool, as there doesn't seem to be a 64-bit tool)
if ((Get-Command "resgen.exe" -ErrorAction SilentlyContinue) -eq $null) {
  $env:Path = "$env:WindowsSDK_ExecutablePath_x86;$env:Path"
}

echo "=== END INSTALL ==="
echo ""

