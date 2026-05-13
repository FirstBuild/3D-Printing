param(
    [string]$CertFile = $null
)

$ErrorActionPreference = "Stop"

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
$targets += "C:\Program Files\OrcaSlicer\resources\cert\printer.cer"

foreach ($target in $targets) {
    Append-CertIfMissing -TargetFile $target -CertText $certText
}

Write-Host ""
Write-Host "Done. Fully quit and restart Bambu Studio / OrcaSlicer."
