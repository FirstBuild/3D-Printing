param(
    [string]$CertFile = $null,
    [switch]$SkipPrinters
)

$ErrorActionPreference = "Stop"

$BambuddyPrintersFile = Join-Path $PSScriptRoot "bambuddy-printers.json"
$BambuddyPrinters = @()

$EmbeddedCertText = @'
-----BEGIN CERTIFICATE-----
MIIC7jCCAdagAwIBAgIUUmyk3xDkK7Y+H0YULvJNkM0tZ0YwDQYJKoZIhvcNAQEL
BQAwHTEbMBkGA1UEAwwSVmlydHVhbCBQcmludGVyIENBMB4XDTI2MDUwNzE0MTAw
NloXDTQ2MDUwMjE0MTAwNlowHTEbMBkGA1UEAwwSVmlydHVhbCBQcmludGVyIENB
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAxkHmyXYLpSCuSvlnQigN
kmFMcfYp+RZRpC3OFYpXykpI9j3KScVzP19S4cuz2oMM+lWH09215sCOPrEbX4fa
XFgMnrNfhY3oWXbyxNXZ5xqPeDu6hS3hXuayKxaFMKJ1i1a9+NlRJRgHOQfBVeON
BXjvhv2ar4BxYXvm0AfLFqh9dRvQEWz3s32incyKn1CvfCjPuU2WfimPEh8oAZwP
wWf6sjVpdcV3GEKid06LubKDECRiA/2sLTP2Y13H2ASZ5aT05M/HAhGvGFNgGmfR
JM8WeyfnWN88/CfEWZcn13QCS4bFiLLFbtfieHSe5NFs3y345sJM825SPeQWhJ3O
HQIDAQABoyYwJDASBgNVHRMBAf8ECDAGAQH/AgEAMA4GA1UdDwEB/wQEAwIBhjAN
BgkqhkiG9w0BAQsFAAOCAQEAYixtxZwX3IX7UuCi6QRiHiMKIsz/lgppLPOlmwce
atUKj3/gxYsIK1y1HzlFvMnh9CKA6O/+TqgRYZ/2Jbvxe+p77l4sUtk9ZkK0AOTv
BBHiNuItJwxHVYlccM9/umOC7pe2z1H0vTAIUsiSIX3mo7C4oOcj9gb9zhSxk7mL
NWzfsPQL+mH9OdNssSAviT90XKymQ0T0W9za0h4mIakTuhW97RriVIng0y6gFGzD
fIWR5OekM5U9z60uXx9YoEdWhp2rQxay+a0GYc+MG5kNuK2P32ho/o2/o8RlzWys
r7K/uMmuVh0cxZctYp29J4BwPlB0wdc5ns8W+vvpUYID+Q==
-----END CERTIFICATE-----
'@

function Normalize-PemText {
    param([string]$Text)

    $t = $Text -replace "`r`n", "`n"
    $t = $t.Trim()

    if ($t -notmatch "-----BEGIN CERTIFICATE-----" -or $t -notmatch "-----END CERTIFICATE-----") {
        throw "Certificate text does not look like a PEM certificate."
    }

    return $t
}

function Append-CertIfMissing {
    param(
        [string]$TargetFile,
        [string]$CertText
    )

    if (-not (Test-Path $TargetFile)) {
        return
    }

    $targetText = Get-Content -Raw -Path $TargetFile
    $normalizedTarget = Normalize-PemText $targetText

    if ($normalizedTarget.Contains($CertText)) {
        Write-Host "Already installed: $TargetFile"
        return
    }

    $backup = "$TargetFile.bak.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item -Path $TargetFile -Destination $backup -Force
    Write-Host "Backup created: $backup"

    $appendText = "`r`n`r`n$($CertText -replace "`n", "`r`n")`r`n"
    Add-Content -Path $TargetFile -Value $appendText -NoNewline

    Write-Host "Installed Bambuddy CA into: $TargetFile"
}

function ConvertTo-ConfigHashtable {
    param([object]$Object)

    if ($null -eq $Object) {
        return @{}
    }

    if ($Object -is [System.Collections.IDictionary]) {
        return $Object
    }

    $hash = @{}
    foreach ($property in $Object.PSObject.Properties) {
        $hash[$property.Name] = $property.Value
    }

    return $hash
}

function ConvertFrom-ConfigJson {
    param([string]$RawText)

    # Some slicer config files append metadata lines like '# MD5: ...' after the JSON body.
    # Strip full-line comments so valid JSON content can still be parsed.
    $textWithoutCommentLines = ($RawText -replace '(?m)^\s*#.*(?:\r?\n|$)', "")
    return $textWithoutCommentLines | ConvertFrom-Json -ErrorAction Stop
}

function Get-BambuddyPrinters {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        throw "Printer definition file not found: $Path"
    }

    $raw = Get-Content -Raw -Path $Path
    $printers = $raw | ConvertFrom-Json -ErrorAction Stop
    $result = @()
    foreach ($printer in $printers) {
        $p = @{
            Name = $printer.name
            Serial = $printer.serial
            Host = $printer.host
            AccessCode = $printer.access_code
        }

        if ($printer.PSObject.Properties.Name -contains "alternate_hosts" -and $null -ne $printer.alternate_hosts) {
            $p.AlternateHosts = @($printer.alternate_hosts)
        }

        $result += $p
    }

    return $result
}

function Write-JsonFile {
    param(
        [string]$Path,
        [object]$Value
    )

    $json = $Value | ConvertTo-Json -Depth 32
    Set-Content -Path $Path -Value $json -Encoding UTF8
}

function Set-ConfigMapValue {
    param(
        [hashtable]$Config,
        [string]$MapName,
        [string]$Serial,
        [string]$Value
    )

    if (-not $Config.ContainsKey($MapName) -or $null -eq $Config[$MapName]) {
        $Config[$MapName] = @{}
    }

    $map = ConvertTo-ConfigHashtable $Config[$MapName]
    $map[$Serial] = $Value
    $Config[$MapName] = $map
}

function ConvertTo-UInt32Wrap {
    param([object]$Value)

    return [uint32](([int64]$Value) -band 4294967295)
}

function Get-BambuFnvSeed {
    param([string]$Text)

    [uint32]$seed = 2166136261
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    foreach ($byte in $bytes) {
        $seed = ConvertTo-UInt32Wrap ($seed -bxor [uint32]$byte)
        $seed = ConvertTo-UInt32Wrap (([uint64]$seed * 16777619))
    }

    return $seed
}

function New-Mt19937State {
    param([uint32]$Seed)

    $mt = New-Object 'UInt32[]' 624
    $mt[0] = $Seed
    for ($i = 1; $i -lt 624; $i++) {
        $x = ConvertTo-UInt32Wrap ($mt[$i - 1] -bxor ($mt[$i - 1] -shr 30))
        $mt[$i] = ConvertTo-UInt32Wrap (([uint64]1812433253 * [uint64]$x + [uint64]$i)
)
    }

    return [pscustomobject]@{
        Mt = $mt
        Index = 624
    }
}

function Invoke-Mt19937Twist {
    param([object]$State)

    for ($i = 0; $i -lt 624; $i++) {
        $y = (($State.Mt[$i] -band 2147483648) + ($State.Mt[($i + 1) % 624] -band 2147483647))
        $value = ConvertTo-UInt32Wrap ($State.Mt[($i + 397) % 624] -bxor (ConvertTo-UInt32Wrap ($y -shr 1)))
        if (($y -band 1) -ne 0) {
            $value = ConvertTo-UInt32Wrap ($value -bxor 2567483615)
        }
        $State.Mt[$i] = ConvertTo-UInt32Wrap $value
    }

    $State.Index = 0
}

function Get-Mt19937Random {
    param([object]$State)

    if ($State.Index -ge 624) {
        Invoke-Mt19937Twist -State $State
    }

    [uint32]$y = $State.Mt[$State.Index]
    $State.Index += 1
    $y = ConvertTo-UInt32Wrap ($y -bxor ($y -shr 11))
    $y = ConvertTo-UInt32Wrap ($y -bxor (($y -shl 7) -band 2636928640))
    $y = ConvertTo-UInt32Wrap ($y -bxor (($y -shl 15) -band 4022730752))
    $y = ConvertTo-UInt32Wrap ($y -bxor ($y -shr 18))

    return (ConvertTo-UInt32Wrap $y)
}

function ConvertTo-BambuEncodedDevIp {
    param(
        [string]$HostName,
        [string]$SlicerUuid
    )

    if ([string]::IsNullOrWhiteSpace($HostName) -or [string]::IsNullOrWhiteSpace($SlicerUuid)) {
        return $HostName
    }

    $state = New-Mt19937State -Seed (Get-BambuFnvSeed -Text $SlicerUuid)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($HostName)
    $parts = foreach ($byte in $bytes) {
        $encoded = $byte -bxor ((Get-Mt19937Random -State $state) -band 0xff)
        "{0:x2}" -f $encoded
    }

    return ($parts -join "")
}

function Test-IPv4Address {
    param([string]$Value)

    $parts = $Value -split '\.'
    if ($parts.Count -ne 4) {
        return $false
    }

    foreach ($part in $parts) {
        $number = 0
        if (-not [int]::TryParse($part, [ref]$number)) {
            return $false
        }
        if ($number -lt 0 -or $number -gt 255) {
            return $false
        }
    }

    return $true
}

function Get-PrinterConnectHost {
    param([hashtable]$Printer)

    if (Test-IPv4Address -Value $Printer.Host) {
        return $Printer.Host
    }

    if ($Printer.ContainsKey("AlternateHosts") -and $Printer.AlternateHosts.Count -gt 0) {
        return $Printer.AlternateHosts[0]
    }

    return $Printer.Host
}

function Get-SlicerUuid {
    param([hashtable]$Config)

    if (-not $Config.ContainsKey("app") -or $null -eq $Config["app"]) {
        $Config["app"] = @{}
    }

    $appConfig = ConvertTo-ConfigHashtable $Config["app"]
    $Config["app"] = $appConfig

    $slicerUuid = $appConfig["slicer_uuid"]
    if ([string]::IsNullOrWhiteSpace($slicerUuid) -and $Config.ContainsKey("slicer_uuid")) {
        $slicerUuid = $Config["slicer_uuid"]
    }

    if ([string]::IsNullOrWhiteSpace($slicerUuid)) {
        $slicerUuid = [guid]::NewGuid().ToString()
    }

    $appConfig["slicer_uuid"] = $slicerUuid
    return $slicerUuid
}

function Configure-Printers {
    if ($SkipPrinters) {
        return
    }

    $configs = @(
        @{
            Path = (Join-Path $env:APPDATA "BambuStudio\BambuStudio.conf")
            Markers = @("C:\Program Files\Bambu Studio", "C:\Program Files (x86)\Bambu Studio")
        },
        @{
            Path = (Join-Path $env:APPDATA "BambuStudioBeta\BambuStudio.conf")
            Markers = @("C:\Program Files\Bambu Studio Beta", "C:\Program Files\BambuStudioBeta", "C:\Program Files (x86)\Bambu Studio Beta", "C:\Program Files (x86)\BambuStudioBeta")
        },
        @{
            Path = (Join-Path $env:APPDATA "OrcaSlicer\OrcaSlicer.conf")
            Markers = @("C:\Program Files\OrcaSlicer", "C:\Program Files (x86)\OrcaSlicer")
        }
    )

    foreach ($configEntry in $configs) {
        $configPath = $configEntry.Path
        $configExists = Test-Path $configPath
        $appExists = $false
        foreach ($marker in $configEntry.Markers) {
            if (Test-Path $marker) {
                $appExists = $true
                break
            }
        }

        if (-not $configExists -and -not $appExists) {
            continue
        }

        $configDir = Split-Path -Parent $configPath
        New-Item -ItemType Directory -Force -Path $configDir | Out-Null

        if (Test-Path $configPath) {
            $raw = Get-Content -Raw -Path $configPath
            if ([string]::IsNullOrWhiteSpace($raw)) {
                $config = @{}
            } else {
                try {
                    $config = ConvertTo-ConfigHashtable (ConvertFrom-ConfigJson -RawText $raw)
                } catch {
                    Write-Warning "Skipping config update for '$configPath' because it is not valid JSON: $($_.Exception.Message)"
                    continue
                }
            }

            $backup = "$configPath.bak.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Copy-Item -Path $configPath -Destination $backup -Force
            Write-Host "Config backup created: $backup"
        } else {
            $config = @{}
        }

        $slicerUuid = Get-SlicerUuid -Config $config

        foreach ($printer in $BambuddyPrinters) {
            $connectHost = Get-PrinterConnectHost -Printer $printer
            Set-ConfigMapValue -Config $config -MapName "access_code" -Serial $printer.Serial -Value $printer.AccessCode
            Set-ConfigMapValue -Config $config -MapName "user_access_code" -Serial $printer.Serial -Value $printer.AccessCode
            Set-ConfigMapValue -Config $config -MapName "ip_address" -Serial $printer.Serial -Value $connectHost
            Set-ConfigMapValue -Config $config -MapName "user_access_dev_ip" -Serial $printer.Serial -Value (ConvertTo-BambuEncodedDevIp -HostName $connectHost -SlicerUuid $slicerUuid)
        }

        Write-JsonFile -Path $configPath -Value $config
        Write-Host "Configured Bambuddy printers in: $configPath"
    }
}

$BambuddyPrinters = Get-BambuddyPrinters -Path $BambuddyPrintersFile

if ($CertFile) {
    if (-not (Test-Path $CertFile)) {
        throw "Certificate file not found: $CertFile"
    }

    $certText = Normalize-PemText (Get-Content -Raw -Path $CertFile)
} else {
    $certText = Normalize-PemText $EmbeddedCertText
}

$targets = @()
$targets += "C:\Program Files\Bambu Studio\resources\cert\printer.cer"
$targets += "C:\Program Files\Bambu Studio Beta\resources\cert\printer.cer"
$targets += "C:\Program Files\BambuStudioBeta\resources\cert\printer.cer"
$targets += "C:\Program Files\OrcaSlicer\resources\cert\printer.cer"

foreach ($target in $targets) {
    Append-CertIfMissing -TargetFile $target -CertText $certText
}

Configure-Printers

Write-Host ""
Write-Host "Done. Fully quit and restart Bambu Studio / Bambu Studio Beta / OrcaSlicer."
