param(
	[string]$GodotPath = "godot"
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$godotCommand = Get-Command $GodotPath -ErrorAction Stop
$godotExecutable = $godotCommand.Source
$outputDirectory = Join-Path $projectRoot "dist"
$voiceSourceDirectory = Join-Path $projectRoot "web\voice"
$voiceOutputDirectory = Join-Path $outputDirectory "voice"

New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

$exportProcess = Start-Process `
	-FilePath $godotExecutable `
	-ArgumentList @("--headless", "--path", ".", "--export-release", "Web", "dist/index.html") `
	-WorkingDirectory $projectRoot `
	-Wait `
	-PassThru `
	-WindowStyle Hidden

if ($exportProcess.ExitCode -ne 0) {
	throw "Godot Web export failed with exit code $($exportProcess.ExitCode)."
}

$requiredFiles = @("index.html", "index.js", "index.pck", "index.wasm")
foreach ($requiredFile in $requiredFiles) {
	$requiredPath = Join-Path $outputDirectory $requiredFile
	if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
		throw "Godot reported success, but $requiredFile was not produced."
	}
}

$exportedHtmlPath = Join-Path $outputDirectory "index.html"
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

$voiceToolbarPath = Join-Path $voiceSourceDirectory "toolbar.html"
$voiceToolbar = Get-Content -LiteralPath $voiceToolbarPath -Raw
$voiceHead = @'
		<meta name="gamer-pub-voice-url" content="wss://joker-multiplayer.joker-multiplayer.workers.dev/voice/tenk">
		<link rel="stylesheet" href="voice/voice.css">
'@
$exportedHtml = $exportedHtml.Replace("`t</head>", "$voiceHead`r`n`t</head>")
$exportedHtml = $exportedHtml.Replace("`t</body>", "$voiceToolbar`r`n`t</body>")
if ($exportedHtml -notmatch 'id="tenk-voice-toolbar"' -or
	$exportedHtml -notmatch 'src="voice/gamer-pub-voice.js"') {
	throw "The Tenk voice toolbar could not be added to the Web export."
}

$normalizedHtml = $exportedHtml.TrimEnd("`r", "`n") + "`n"
[System.IO.File]::WriteAllText(
	$exportedHtmlPath,
	$normalizedHtml,
	[System.Text.UTF8Encoding]::new($false)
)

Write-Output "Web export ready in $outputDirectory"
