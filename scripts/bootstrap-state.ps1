[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("staging", "production")]
    [string]$Environment,

    [Parameter(Mandatory = $true)]
    [ValidatePattern("^[a-z0-9-]+$")]
    [string]$Region,

    [Parameter(Mandatory = $true)]
    [ValidatePattern("^[0-9]{12}$")]
    [string]$ExpectedAccountId
)

$ErrorActionPreference = "Stop"
$Environment = $Environment.ToLowerInvariant()
$Region = $Region.ToLowerInvariant()
$projectRoot = Split-Path -Parent $PSScriptRoot
$backendPath = Join-Path $projectRoot "terraform\environments\$Environment\backend.hcl"
if (Test-Path -LiteralPath $backendPath) {
    throw "Backend configuration already exists at $backendPath. Inspect it instead of creating another state bucket."
}

function Invoke-Aws {
    param([string[]]$Arguments)

    $result = & aws @Arguments --region $Region --output json --no-cli-pager 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "AWS CLI failed (exit $LASTEXITCODE): $($result -join [Environment]::NewLine)"
    }
    return ($result -join [Environment]::NewLine)
}

$identity = (Invoke-Aws @("sts", "get-caller-identity")) | ConvertFrom-Json
if ($identity.Account -ne $ExpectedAccountId) {
    throw "Current AWS account does not match ExpectedAccountId. No bucket was created."
}

# A fresh random name avoids taking over or changing a pre-existing bucket.
$bucket = "one-step-v1-$Environment-state-$([Guid]::NewGuid().ToString('N'))"
$key = "one-step-at-a-time/$Environment/terraform.tfstate"
if (-not $PSCmdlet.ShouldProcess("AWS account $ExpectedAccountId, region $Region", "Create state bucket $bucket for $Environment")) {
    return
}

$creationAttempted = $false
$policyFile = $null
try {
    $createArguments = @("s3api", "create-bucket", "--bucket", $bucket)
    if ($Region -ne "us-east-1") {
        $createArguments += @("--create-bucket-configuration", "LocationConstraint=$Region")
    }
    $creationAttempted = $true
    $null = Invoke-Aws $createArguments

    $owner = @("--expected-bucket-owner", $ExpectedAccountId)
    $null = Invoke-Aws (@(
        "s3api", "put-public-access-block", "--bucket", $bucket,
        "--public-access-block-configuration",
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
    ) + $owner)
    $null = Invoke-Aws (@(
        "s3api", "put-bucket-versioning", "--bucket", $bucket,
        "--versioning-configuration", "Status=Enabled"
    ) + $owner)
    $null = Invoke-Aws (@(
        "s3api", "put-bucket-encryption", "--bucket", $bucket,
        "--server-side-encryption-configuration",
        "Rules=[{ApplyServerSideEncryptionByDefault={SSEAlgorithm=AES256}}]"
    ) + $owner)

    $policy = @{
        Version = "2012-10-17"
        Statement = @(@{
            Sid = "DenyInsecureTransport"
            Effect = "Deny"
            Principal = "*"
            Action = "s3:*"
            Resource = @("arn:aws:s3:::$bucket", "arn:aws:s3:::$bucket/*")
            Condition = @{ Bool = @{ "aws:SecureTransport" = "false" } }
        })
    } | ConvertTo-Json -Depth 10 -Compress
    $policyFile = Join-Path ([System.IO.Path]::GetTempPath()) ("one-step-state-policy-" + [Guid]::NewGuid().ToString("N") + ".json")
    [System.IO.File]::WriteAllText($policyFile, $policy, (New-Object System.Text.UTF8Encoding($false)))
    $null = Invoke-Aws (@("s3api", "put-bucket-policy", "--bucket", $bucket, "--policy", "file://$policyFile") + $owner)

    $access = (Invoke-Aws (@("s3api", "get-public-access-block", "--bucket", $bucket) + $owner)) | ConvertFrom-Json
    $versioning = (Invoke-Aws (@("s3api", "get-bucket-versioning", "--bucket", $bucket) + $owner)) | ConvertFrom-Json
    $encryption = (Invoke-Aws (@("s3api", "get-bucket-encryption", "--bucket", $bucket) + $owner)) | ConvertFrom-Json
    $storedPolicy = (Invoke-Aws (@("s3api", "get-bucket-policy", "--bucket", $bucket) + $owner)) | ConvertFrom-Json
    $storedPolicy = $storedPolicy.Policy | ConvertFrom-Json
    $location = (Invoke-Aws (@("s3api", "get-bucket-location", "--bucket", $bucket) + $owner)) | ConvertFrom-Json
    $actualRegion = $location.LocationConstraint
    if (-not $actualRegion) { $actualRegion = "us-east-1" }

    $block = $access.PublicAccessBlockConfiguration
    if (-not ($block.BlockPublicAcls -and $block.IgnorePublicAcls -and $block.BlockPublicPolicy -and $block.RestrictPublicBuckets)) {
        throw "Public access block verification failed."
    }
    if ($versioning.Status -ne "Enabled") { throw "Bucket versioning verification failed." }
    if (@($encryption.ServerSideEncryptionConfiguration.Rules | Where-Object { $_.ApplyServerSideEncryptionByDefault.SSEAlgorithm -eq "AES256" }).Count -eq 0) {
        throw "Bucket encryption verification failed."
    }
    $tls = @($storedPolicy.Statement | Where-Object { $_.Sid -eq "DenyInsecureTransport" })
    if ($tls.Count -ne 1 -or $tls[0].Effect -ne "Deny" -or $tls[0].Principal -ne "*" -or
        $tls[0].Action -ne "s3:*" -or $tls[0].Condition.Bool."aws:SecureTransport" -ne "false" -or
        "arn:aws:s3:::$bucket" -notin $tls[0].Resource -or "arn:aws:s3:::$bucket/*" -notin $tls[0].Resource) {
        throw "TLS-only bucket policy verification failed."
    }
    if ($actualRegion -ne $Region) { throw "Bucket region verification failed: expected $Region, got $actualRegion." }

    $backend = "bucket = `"$bucket`"`nkey    = `"$key`"`nregion = `"$Region`"`n"
    # CreateNew refuses to overwrite a backend created by another process.
    $file = [System.IO.File]::Open($backendPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)
    try {
        $writer = New-Object System.IO.StreamWriter($file, (New-Object System.Text.UTF8Encoding($false)))
        try { $writer.Write($backend) } finally { $writer.Dispose() }
    } finally {
        $file.Dispose()
    }
    Write-Host "Created and verified state bucket: $bucket"
    Write-Host "Created backend configuration: $backendPath"
    Write-Host "The bucket is separate from the website and must be reviewed separately during teardown."
} catch {
    if ($creationAttempted) {
        throw "Bootstrap did not finish. Bucket $bucket may still exist in account $ExpectedAccountId and region $Region. Inspect it and its backend file before retrying. Original error: $($_.Exception.Message)"
    }
    throw
} finally {
    if ($policyFile -and (Test-Path -LiteralPath $policyFile)) {
        Remove-Item -LiteralPath $policyFile -ErrorAction Stop
    }
}
