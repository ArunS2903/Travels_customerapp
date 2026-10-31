param(
    [string]$ApiBaseUrl,
    [string]$DeviceId
)

$ErrorActionPreference = 'Stop'
$appRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$propertiesPath = Join-Path $appRoot 'android\local.properties'

if (-not (Test-Path $propertiesPath)) {
    throw "Missing $propertiesPath. Open the Flutter project once in Android Studio or set flutter.sdk in local.properties."
}

$flutterLine = Select-String -Path $propertiesPath -Pattern '^flutter\.sdk=(.+)$' | Select-Object -First 1
if (-not $flutterLine) { throw 'flutter.sdk is not set in android\local.properties.' }
$flutterSdk = $flutterLine.Matches.Groups[1].Value -replace '\\\\', '\'
$flutter = Join-Path $flutterSdk 'bin\flutter.bat'
if (-not (Test-Path $flutter)) { throw "Flutter SDK not found at $flutterSdk. Update flutter.sdk in android\local.properties." }
$sdkLine = Select-String -Path $propertiesPath -Pattern '^sdk\.dir=(.+)$' | Select-Object -First 1
$adb = $null
if ($sdkLine) {
    $androidSdk = $sdkLine.Matches.Groups[1].Value -replace '\\\\', '\'
    $adbPath = Join-Path $androidSdk 'platform-tools\adb.exe'
    if (Test-Path $adbPath) { $adb = $adbPath }
}

Push-Location $appRoot
try {
    $devicesJson = & $flutter devices --machine
    if ($LASTEXITCODE -ne 0) { throw 'Could not read Flutter devices. Run flutter doctor -v for Android SDK setup.' }
    $devices = @($devicesJson | ConvertFrom-Json)
    $androidDevices = @($devices | Where-Object { $_.targetPlatform -like 'android-*' })

    if ($androidDevices.Count -eq 0) {
        Write-Host 'No Android device is visible to Flutter.' -ForegroundColor Yellow
        Write-Host 'Connect the phone with USB debugging enabled and approve its prompt.'
        if ($adb) { Write-Host ('Check the USB connection with: "{0}" devices -l' -f $adb) }
        else { Write-Host 'Check the USB connection with: adb devices -l' }
        Write-Host 'Or start an emulator in Android Studio Device Manager.'
        exit 2
    }

    if ($DeviceId) {
        $device = $androidDevices | Where-Object { $_.id -eq $DeviceId } | Select-Object -First 1
        if (-not $device) {
            $available = ($androidDevices | ForEach-Object { "$($_.name) ($($_.id))" }) -join ', '
            throw "Android device '$DeviceId' was not found. Available Android devices: $available"
        }
    } else {
        $device = $androidDevices[0]
    }

    if (-not $ApiBaseUrl) {
        if ($device.emulator) {
            $ApiBaseUrl = 'http://10.0.2.2:5000/api/v1'
        } else {
            $reverseReady = $false
            if ($adb) {
                Write-Host "Setting up USB API forwarding for $($device.name)..."
                & $adb -s $device.id reverse tcp:5000 tcp:5000 | Out-Null
                $reverseReady = $LASTEXITCODE -eq 0
            }

            if ($reverseReady) {
                $ApiBaseUrl = 'http://127.0.0.1:5000/api/v1'
            } else {
                $lanConfig = Get-NetIPConfiguration |
                    Where-Object { $_.IPv4DefaultGateway -and $_.IPv4Address } |
                    Select-Object -First 1
                $lanIp = $lanConfig.IPv4Address.IPAddress
                if (-not $lanIp) {
                    throw 'USB port forwarding failed and no PC LAN IP was found. Pass -ApiBaseUrl http://<PC-IP>:5000/api/v1 explicitly.'
                }
                Write-Host 'USB forwarding was unavailable; using the PC LAN address. The phone must be on the same Wi-Fi.'
                $ApiBaseUrl = "http://${lanIp}:5000/api/v1"
            }
        }
    }

    Write-Host "Running on $($device.name) using API $ApiBaseUrl"
    & $flutter run -d $device.id --dart-define="API_BASE_URL=$ApiBaseUrl"
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
