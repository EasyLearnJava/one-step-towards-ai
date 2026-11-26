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

# Creates or checks the Terraform state bucket for one environment.
#   - No backend.hcl: creates a new private, versioned, encrypted, HTTPS-only
#     bucket, verifies it, then writes backend.hcl.
#   - backend.hcl present: reads the bucket it names, reports each setting as
#     already applied or missing, and applies only what is missing after you
#     confirm. Nothing is changed when everything is already applied.
# It never creates a second bucket for an environment and never rewrites an
# existing backend.hcl. -WhatIf shows what would happen without changing AWS.

$ErrorActionPreference = "Stop"
$Environment = $Environment.ToLowerInvariant()
$Region = $Region.ToLowerInvariant()
$projectRoot = Split-Path -Parent $PSScriptRoot
# Nested Join-Path keeps the path valid on Windows and in PowerShell 7 elsewhere.
$backendPath = Join-Path $projectRoot (Join-Path "terraform" (Join-Path "environments" (Join-Path $Environment "backend.hcl")))
$defaultKey = "one-step-at-a-time/$Environment/terraform.tfstate"
$ownerArgs = @("--expected-bucket-owner", $ExpectedAccountId)

function Invoke-AwsRaw {
    # Runs the AWS CLI and returns its exit code and output without throwing, so
    # expected answers such as "no bucket policy" can be handled. Windows
    # PowerShell 5.1 turns redirected stderr into a terminating error under
    # "Stop", so this function uses "Continue" for its own scope only.
    # On success Text is stdout only, so a CLI warning on stderr cannot break
    # the JSON; on failure it is stderr followed by stdout.
    param([string[]]$Arguments)

    $ErrorActionPreference = "Continue"
    $output = & aws @Arguments --region $Region --output json --no-cli-pager 2>&1
    $code = $LASTEXITCODE
    # "$_" turns stderr records into text and copes with no output at all.
    $stdout = @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_" })
    $stderr = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_" })
    $text = $stdout -join [Environment]::NewLine
    if ($code -ne 0) { $text = ($stderr + $stdout) -join [Environment]::NewLine }
    return [pscustomobject]@{ ExitCode = $code; Text = $text }
}

function Invoke-Aws {
    param([string[]]$Arguments)

    $result = Invoke-AwsRaw $Arguments
    if ($result.ExitCode -ne 0) {
        throw "AWS CLI failed (exit $($result.ExitCode)): $($result.Text)"
    }
    return $result.Text
}

function Read-BackendFile {
    # Reads bucket, key and region from backend.hcl; comment lines are ignored.
    param([string]$Path)

    $values = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^\s*(bucket|key|region)\s*=\s*"([^"]*)"\s*$') {
            $values[$Matches[1]] = $Matches[2]
        }
    }
    return $values
}

function Get-BucketRegion {
    param([string]$Bucket)

    $location = (Invoke-Aws (@("s3api", "get-bucket-location", "--bucket", $Bucket) + $ownerArgs)) | ConvertFrom-Json
    $actual = $location.LocationConstraint
    if (-not $actual) { $actual = "us-east-1" }
    return $actual
}

function Test-TlsOnlyPolicy {
    # True when the policy has a Deny for all principals and all S3 actions on
    # the bucket and its objects whenever aws:SecureTransport is false. Any
    # extra condition would narrow the Deny, so aws:SecureTransport must be its
    # only condition.
    param($Policy, [string]$Bucket)

    $needed = @("arn:aws:s3:::$Bucket", "arn:aws:s3:::$Bucket/*")
    foreach ($statement in @($Policy.Statement)) {
        if ($statement.Effect -ne "Deny") { continue }
        $allPrincipals = ($statement.Principal -eq "*") -or ($statement.Principal.AWS -eq "*")
        $secure = $null
        if ($statement.Condition -and $statement.Condition.Bool -and
            @($statement.Condition.PSObject.Properties).Count -eq 1 -and
            @($statement.Condition.Bool.PSObject.Properties).Count -eq 1) {
            $secure = $statement.Condition.Bool."aws:SecureTransport"
        }
        $resources = @($statement.Resource)
        $missingResources = @($needed | Where-Object { $_ -notin $resources })
        if ($allPrincipals -and (@($statement.Action) -contains "s3:*") -and ("$secure" -eq "false") -and $missingResources.Count -eq 0) {
            return $true
        }
    }
    return $false
}

function Get-BucketState {
    # Reads the four settings this script manages. "Not configured" answers
    # from S3 count as missing; any other error stops the script.
    param([string]$Bucket)

    $state = [pscustomobject]@{
        PublicAccessBlocked = $false
        VersioningEnabled   = $false
        Encryption          = $null
        Policy              = $null
        TlsOnly             = $false
    }

    $result = Invoke-AwsRaw (@("s3api", "get-public-access-block", "--bucket", $Bucket) + $ownerArgs)
    if ($result.ExitCode -eq 0) {
        $block = ($result.Text | ConvertFrom-Json).PublicAccessBlockConfiguration
        $state.PublicAccessBlocked = [bool]($block.BlockPublicAcls -and $block.IgnorePublicAcls -and $block.BlockPublicPolicy -and $block.RestrictPublicBuckets)
    } elseif ($result.Text -notmatch "NoSuchPublicAccessBlockConfiguration") {
        throw "Could not read the public access block of ${Bucket}: $($result.Text)"
    }

    $versioning = Invoke-Aws (@("s3api", "get-bucket-versioning", "--bucket", $Bucket) + $ownerArgs)
    # The output is empty when versioning has never been enabled.
    if ($versioning.Trim()) {
        $state.VersioningEnabled = (($versioning | ConvertFrom-Json).Status -eq "Enabled")
    }

    $result = Invoke-AwsRaw (@("s3api", "get-bucket-encryption", "--bucket", $Bucket) + $ownerArgs)
    if ($result.ExitCode -eq 0) {
        $rules = @(($result.Text | ConvertFrom-Json).ServerSideEncryptionConfiguration.Rules)
        $algorithms = @($rules | ForEach-Object { $_.ApplyServerSideEncryptionByDefault.SSEAlgorithm } | Where-Object { $_ })
        if ($algorithms.Count -gt 0) { $state.Encryption = $algorithms[0] }
    } elseif ($result.Text -notmatch "ServerSideEncryptionConfigurationNotFoundError") {
        throw "Could not read the encryption of ${Bucket}: $($result.Text)"
    }

    $result = Invoke-AwsRaw (@("s3api", "get-bucket-policy", "--bucket", $Bucket) + $ownerArgs)
    if ($result.ExitCode -eq 0) {
        $state.Policy = ($result.Text | ConvertFrom-Json).Policy | ConvertFrom-Json
        $state.TlsOnly = Test-TlsOnlyPolicy $state.Policy $Bucket
    } elseif ($result.Text -notmatch "NoSuchBucketPolicy") {
        throw "Could not read the bucket policy of ${Bucket}: $($result.Text)"
    }

    return $state
}

function Show-BucketState {
    # Prints one line per setting and returns the names of missing settings.
    param($State)

    $encryptionLabel = "Default encryption"
    if ($State.Encryption) { $encryptionLabel = "Default encryption ($($State.Encryption))" }
    $checks = @(
        @("Public access block (all four settings on)", $State.PublicAccessBlocked),
        @("Versioning enabled", $State.VersioningEnabled),
        @($encryptionLabel, [bool]$State.Encryption),
        @("HTTPS-only bucket policy", $State.TlsOnly)
    )
    $missing = @()
    foreach ($check in $checks) {
        if ($check[1]) {
            Write-Host "[OK]      $($check[0]): already applied"
        } else {
            Write-Host "[MISSING] $($check[0])"
            $missing += $check[0]
        }
    }
    return $missing
}

function Set-BucketSettings {
    # Applies only the settings that $State reports as missing. An existing
    # bucket policy keeps all its other statements; only the HTTPS-only
    # statement is added or replaced.
    param([string]$Bucket, $State)

    if (-not $State.PublicAccessBlocked) {
        $null = Invoke-Aws (@(
            "s3api", "put-public-access-block", "--bucket", $Bucket,
            "--public-access-block-configuration",
            "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
        ) + $ownerArgs)
        Write-Host "Applied: public access block"
    }
    if (-not $State.VersioningEnabled) {
        $null = Invoke-Aws (@("s3api", "put-bucket-versioning", "--bucket", $Bucket, "--versioning-configuration", "Status=Enabled") + $ownerArgs)
        Write-Host "Applied: versioning"
    }
    if (-not $State.Encryption) {
        $null = Invoke-Aws (@(
            "s3api", "put-bucket-encryption", "--bucket", $Bucket,
            "--server-side-encryption-configuration",
            "Rules=[{ApplyServerSideEncryptionByDefault={SSEAlgorithm=AES256}}]"
        ) + $ownerArgs)
        Write-Host "Applied: default encryption (AES256)"
    }
    if (-not $State.TlsOnly) {
        $tlsStatement = [pscustomobject][ordered]@{
            Sid       = "DenyInsecureTransport"
            Effect    = "Deny"
            Principal = "*"
            Action    = "s3:*"
            Resource  = @("arn:aws:s3:::$Bucket", "arn:aws:s3:::$Bucket/*")
            Condition = @{ Bool = @{ "aws:SecureTransport" = "false" } }
        }
        $version = "2012-10-17"
        $statements = @()
        if ($State.Policy) {
            if ($State.Policy.Version) { $version = $State.Policy.Version }
            $statements = @(@($State.Policy.Statement) | Where-Object { $_.Sid -ne "DenyInsecureTransport" })
        }
        $policy = [ordered]@{ Version = $version; Statement = @($statements) + @($tlsStatement) } | ConvertTo-Json -Depth 20 -Compress
        $policyFile = Join-Path ([System.IO.Path]::GetTempPath()) ("tf-state-policy-" + [Guid]::NewGuid().ToString("N") + ".json")
        try {
            [System.IO.File]::WriteAllText($policyFile, $policy, (New-Object System.Text.UTF8Encoding($false)))
            $null = Invoke-Aws (@("s3api", "put-bucket-policy", "--bucket", $Bucket, "--policy", "file://$policyFile") + $ownerArgs)
        } finally {
            if (Test-Path -LiteralPath $policyFile) { Remove-Item -LiteralPath $policyFile -ErrorAction Stop }
        }
        Write-Host "Applied: HTTPS-only bucket policy"
    }
}

function Assert-BucketReady {
    # Reads every setting back from AWS and stops if any is still missing.
    param([string]$Bucket)

    $actualRegion = Get-BucketRegion $Bucket
    if ($actualRegion -ne $Region) { throw "Bucket region verification failed: expected $Region, got $actualRegion." }
    $state = Get-BucketState $Bucket
    $failed = @()
    if (-not $state.PublicAccessBlocked) { $failed += "public access block" }
    if (-not $state.VersioningEnabled) { $failed += "versioning" }
    if (-not $state.Encryption) { $failed += "default encryption" }
    if (-not $state.TlsOnly) { $failed += "HTTPS-only bucket policy" }
    if ($failed.Count -gt 0) { throw "Verification failed for bucket ${Bucket}: $($failed -join ', ')." }
}

# --- Step 1: the AWS CLI must use the intended account -----------------------
$identity = (Invoke-Aws @("sts", "get-caller-identity")) | ConvertFrom-Json
if ($identity.Account -ne $ExpectedAccountId) {
    throw "Current AWS account does not match ExpectedAccountId. No AWS change was made."
}
Write-Host "[OK]      AWS CLI account matches ExpectedAccountId"

# --- Step 2a: backend.hcl exists, so check its bucket instead of creating one -
if (Test-Path -LiteralPath $backendPath) {
    Write-Host "Found $backendPath; checking the bucket it names. No new bucket will be created."
    $backend = Read-BackendFile $backendPath
    $bucket = $backend["bucket"]
    if (-not $bucket) {
        throw "backend.hcl has no bucket = `"...`" line. Fix the file; no AWS change was made."
    }
    if ($bucket -notmatch '^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$') {
        throw "backend.hcl bucket '$bucket' is not a valid S3 bucket name. Fix the file; no AWS change was made."
    }
    if ($backend["region"] -and $backend["region"] -ne $Region) {
        throw "backend.hcl uses region $($backend["region"]) but -Region is $Region. Run again with -Region $($backend["region"]); no AWS change was made."
    }

    $head = Invoke-AwsRaw (@("s3api", "head-bucket", "--bucket", $bucket) + $ownerArgs)
    if ($head.ExitCode -ne 0) {
        throw "Bucket $bucket named in backend.hcl was not found in account $ExpectedAccountId, or you cannot access it. Check the name in backend.hcl; to create a new bucket instead, move backend.hcl aside first. No AWS change was made. Details: $($head.Text)"
    }
    Write-Host "[OK]      Bucket $bucket exists and belongs to account $ExpectedAccountId"

    $actualRegion = Get-BucketRegion $bucket
    if ($actualRegion -ne $Region) {
        throw "Bucket $bucket is in $actualRegion, not $Region. Fix backend.hcl and -Region; no AWS change was made."
    }
    Write-Host "[OK]      Bucket region is $Region"

    $key = $backend["key"]
    if (-not $key) { $key = $defaultKey }
    if ($key -ne $defaultKey) {
        Write-Host "[INFO]    backend.hcl uses key $key (default would be $defaultKey); keeping it."
    }
    # Only "not found" means there is no state yet; any other error (for example
    # access denied) stops the script instead of being reported as "no state".
    $object = Invoke-AwsRaw (@("s3api", "head-object", "--bucket", $bucket, "--key", $key) + $ownerArgs)
    if ($object.ExitCode -eq 0) {
        Write-Host "[INFO]    Terraform state file found at $key"
    } elseif ($object.Text -match '\((404|NoSuchKey|NotFound)\)') {
        Write-Host "[INFO]    No Terraform state file at $key yet (normal before the first apply)"
    } else {
        throw "Could not check the Terraform state file at ${key}. No AWS change was made. Details: $($object.Text)"
    }

    $state = Get-BucketState $bucket
    $missing = @(Show-BucketState $state)
    if ($missing.Count -eq 0) {
        Write-Host "Everything is already applied. Nothing was changed; backend.hcl was left as it is."
        return
    }
    if (-not $PSCmdlet.ShouldProcess("bucket $bucket in account $ExpectedAccountId", "Apply missing settings: $($missing -join '; ')")) {
        return
    }
    Set-BucketSettings $bucket $state
    Assert-BucketReady $bucket
    Write-Host "Applied the missing settings and verified bucket $bucket. backend.hcl was left as it is."
    return
}

# --- Step 2b: no backend.hcl, so create a new bucket and write backend.hcl ----
# A fresh random name avoids taking over or changing a pre-existing bucket.
$bucket = "one-step-v1-$Environment-state-$([Guid]::NewGuid().ToString('N'))"
if (-not $PSCmdlet.ShouldProcess("AWS account $ExpectedAccountId, region $Region", "Create state bucket $bucket for $Environment")) {
    return
}

$creationAttempted = $false
try {
    $createArguments = @("s3api", "create-bucket", "--bucket", $bucket)
    if ($Region -ne "us-east-1") {
        $createArguments += @("--create-bucket-configuration", "LocationConstraint=$Region")
    }
    $creationAttempted = $true
    $null = Invoke-Aws $createArguments

    # A new bucket is treated as having nothing applied, so every setting is set explicitly.
    $fresh = [pscustomobject]@{ PublicAccessBlocked = $false; VersioningEnabled = $false; Encryption = $null; Policy = $null; TlsOnly = $false }
    Set-BucketSettings $bucket $fresh
    Assert-BucketReady $bucket

    $backendText = "bucket = `"$bucket`"`nkey    = `"$defaultKey`"`nregion = `"$Region`"`n"
    # CreateNew refuses to overwrite a backend created by another process.
    $file = [System.IO.File]::Open($backendPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)
    try {
        $writer = New-Object System.IO.StreamWriter($file, (New-Object System.Text.UTF8Encoding($false)))
        try { $writer.Write($backendText) } finally { $writer.Dispose() }
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
}
