param(
	[string]$GodotPath = "godot"
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path

function Resolve-GodotExecutable {
	param([string]$RequestedPath)

	if (Test-Path -LiteralPath $RequestedPath -PathType Leaf) {
		return (Resolve-Path -LiteralPath $RequestedPath).Path
	}

	$requestedCommand = Get-Command $RequestedPath -CommandType Application -ErrorAction SilentlyContinue |
		Select-Object -First 1
	if ($null -ne $requestedCommand -and -not [string]::IsNullOrWhiteSpace($requestedCommand.Path)) {
		return $requestedCommand.Path
	}

	if ($RequestedPath -eq "godot") {
		$versionedCommand = Get-Command `
			@("godot.exe", "Godot_v*-stable_win64_console.exe", "Godot_v*-stable_win64.exe") `
			-CommandType Application `
			-ErrorAction SilentlyContinue |
			Select-Object -First 1
		if ($null -ne $versionedCommand -and -not [string]::IsNullOrWhiteSpace($versionedCommand.Path)) {
			return $versionedCommand.Path
		}
	}

	throw "Godot executable '$RequestedPath' was not found. Pass -GodotPath with the full path to your Godot executable."
}

$godotExecutable = Resolve-GodotExecutable $GodotPath
$buildDirectory = Join-Path $projectRoot "build"
$godotOutputDirectory = Join-Path $buildDirectory "web"
$outputDirectory = Join-Path $projectRoot "dist"
$activityDirectory = Join-Path $projectRoot "activity"
$voiceSourceDirectory = Join-Path $projectRoot "web\voice"
$voiceOutputDirectory = Join-Path $godotOutputDirectory "voice"
$cribbageSourceDirectory = Join-Path $projectRoot "web\cribbage"
$cribbageOutputDirectory = Join-Path $godotOutputDirectory "cribbage"

New-Item -ItemType Directory -Path $godotOutputDirectory -Force | Out-Null
[System.IO.File]::WriteAllText(
	(Join-Path $buildDirectory ".gdignore"),
	"",
	[System.Text.UTF8Encoding]::new($false)
)

$exportProcess = Start-Process `
	-FilePath $godotExecutable `
	-ArgumentList @("--headless", "--path", ".", "--export-release", "Web", "build/web/index.html") `
	-WorkingDirectory $projectRoot `
	-Wait `
	-PassThru `
	-WindowStyle Hidden

if ($exportProcess.ExitCode -ne 0) {
	throw "Godot Web export failed with exit code $($exportProcess.ExitCode)."
}

$requiredFiles = @("index.html", "index.js", "index.pck", "index.wasm")
foreach ($requiredFile in $requiredFiles) {
	$requiredPath = Join-Path $godotOutputDirectory $requiredFile
	if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
		throw "Godot reported success, but $requiredFile was not produced."
	}
}

$exportedHtmlPath = Join-Path $godotOutputDirectory "index.html"
$exportedHtml = Get-Content -LiteralPath $exportedHtmlPath -Raw
if ($exportedHtml -notmatch "const GODOT_THREADS_ENABLED = false;") {
	throw "The Web export unexpectedly enabled threads. Netlify play-test headers are configured for a single-threaded build."
}

$voiceFiles = @(
	"gamer-pub-voice.js",
	"microphone-controller.js",
	"voice-chat.js",
	"voice-room-client.js",
	"voice.css"
)
New-Item -ItemType Directory -Path $voiceOutputDirectory -Force | Out-Null
foreach ($voiceFile in $voiceFiles) {
	$voiceSourcePath = Join-Path $voiceSourceDirectory $voiceFile
	if (-not (Test-Path -LiteralPath $voiceSourcePath -PathType Leaf)) {
		throw "Voice asset $voiceFile is missing."
	}
	Copy-Item -LiteralPath $voiceSourcePath -Destination (Join-Path $voiceOutputDirectory $voiceFile) -Force
}
New-Item -ItemType Directory -Path $cribbageOutputDirectory -Force | Out-Null
$cribbageFiles = @("cribbage-room.js", "cribbage-room-client.js")
foreach ($cribbageFile in $cribbageFiles) {
	$cribbageSourcePath = Join-Path $cribbageSourceDirectory $cribbageFile
	if (-not (Test-Path -LiteralPath $cribbageSourcePath -PathType Leaf)) {
		throw "Cribbage browser asset $cribbageFile is missing."
	}
	Copy-Item -LiteralPath $cribbageSourcePath -Destination (Join-Path $cribbageOutputDirectory $cribbageFile) -Force
}

$voiceToolbarPath = Join-Path $voiceSourceDirectory "toolbar.html"
$voiceToolbar = Get-Content -LiteralPath $voiceToolbarPath -Raw
$voiceHead = @'
		<meta name="gamer-pub-voice-url" content="wss://gamerpub-multiplayer.joker-multiplayer.workers.dev/tenk">
		<meta name="gamer-pub-cribbage-url" content="wss://gamerpub-multiplayer.joker-multiplayer.workers.dev/cribbage">
		<link rel="stylesheet" href="voice/voice.css">
'@
$exportedHtml = $exportedHtml.Replace("`t</head>", "$voiceHead`r`n`t</head>")
$cribbageScript = "`t<script type=`"module`" src=`"cribbage/cribbage-room.js`"></script>"
$exportedHtml = $exportedHtml.Replace("`t</body>", "$voiceToolbar`r`n$cribbageScript`r`n`t</body>")
if ($exportedHtml -notmatch 'id="tenk-voice-toolbar"' -or
	$exportedHtml -notmatch 'src="voice/gamer-pub-voice.js"' -or
	$exportedHtml -notmatch 'src="cribbage/cribbage-room.js"') {
	throw "The Tenk voice toolbar could not be added to the Web export."
}

$normalizedHtml = $exportedHtml.TrimEnd("`r", "`n") + "`n"
[System.IO.File]::WriteAllText(
	$exportedHtmlPath,
	$normalizedHtml,
	[System.Text.UTF8Encoding]::new($false)
)

$npmCommand = Get-Command "npm.cmd" -ErrorAction SilentlyContinue
if ($null -eq $npmCommand) {
	$npmCommand = Get-Command "npm" -ErrorAction Stop
}
$activityModules = Join-Path $activityDirectory "node_modules\@discord\embedded-app-sdk"
if (-not (Test-Path -LiteralPath $activityModules -PathType Container)) {
	$installProcess = Start-Process `
		-FilePath $npmCommand.Source `
		-ArgumentList @("ci") `
		-WorkingDirectory $activityDirectory `
		-Wait `
		-PassThru `
		-WindowStyle Hidden
	if ($installProcess.ExitCode -ne 0) {
		throw "The Gamer Pub Activity dependencies failed to install with exit code $($installProcess.ExitCode)."
	}
}

$activityBuild = Start-Process `
	-FilePath $npmCommand.Source `
	-ArgumentList @("run", "build") `
	-WorkingDirectory $activityDirectory `
	-Wait `
	-PassThru `
	-WindowStyle Hidden
if ($activityBuild.ExitCode -ne 0) {
	throw "The Gamer Pub Activity build failed with exit code $($activityBuild.ExitCode)."
}

$activityRequiredFiles = @("index.html", "game-manifest.json", "_headers")
foreach ($requiredFile in $activityRequiredFiles) {
	$requiredPath = Join-Path $outputDirectory $requiredFile
	if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
		throw "The Activity build reported success, but dist/$requiredFile was not produced."
	}
}
if (-not (Test-Path -LiteralPath (Join-Path $outputDirectory "game") -PathType Container)) {
	throw "The Activity build did not include the versioned Godot game bundle."
}

Write-Output "Discord Activity and Web deployment ready in $outputDirectory"
