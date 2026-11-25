param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("capture", "verify")]
    [string]$Mode,

    [Parameter(Mandatory = $true)]
    [string]$Inventory
)

$ErrorActionPreference = "Stop"

function Invoke-JsonCommand {
    param([string]$Command, [string[]]$Arguments)

    $result = & $Command @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "$Command failed (exit $LASTEXITCODE): $($result -join [Environment]::NewLine)"
    }
    return ($result -join [Environment]::NewLine | ConvertFrom-Json)
}

function Get-AwsJson {
    param([string[]]$Arguments)

    return Invoke-JsonCommand "aws" ($Arguments + @("--region", "us-east-1", "--output", "json", "--no-cli-pager"))
}

$identity = Get-AwsJson @("sts", "get-caller-identity")
if (-not $identity.Account) {
    throw "AWS did not return an account ID."
}

if ($Mode -eq "capture") {
    if (Test-Path -LiteralPath $Inventory) {
        throw "Inventory already exists: $Inventory. Choose a new file to avoid overwriting a previous inventory."
    }

    $state = Invoke-JsonCommand "terraform" @("show", "-json")
    $root = $state.values.root_module
    if (-not $root -or @($root.child_modules).Count -gt 0 -and $root.child_modules) {
        throw "Expected a root-only Terraform state. Review the configuration before capturing an inventory."
    }
    $accountData = @($root.resources | Where-Object { $_.address -eq "data.aws_caller_identity.current" })
    if ($accountData.Count -ne 1 -or $accountData[0].values.account_id -ne $identity.Account) {
        throw "The Terraform state account does not match the current AWS CLI account. Recheck the environment and credentials."
    }
    $resources = @($root.resources | Where-Object { $_.mode -eq "managed" })
    $expectedTypes = @(
        "aws_s3_bucket", "aws_s3_bucket_public_access_block",
        "aws_s3_bucket_ownership_controls", "aws_s3_bucket_versioning",
        "aws_s3_bucket_server_side_encryption_configuration", "aws_s3_bucket_policy",
        "aws_cloudfront_origin_access_control", "aws_cloudfront_response_headers_policy",
        "aws_cloudfront_distribution", "aws_iam_role", "aws_iam_role_policy",
        "aws_route53_health_check", "aws_sns_topic", "aws_sns_topic_subscription",
        "aws_cloudwatch_metric_alarm"
    )
    $unknown = @($resources | Where-Object { $_.type -notin $expectedTypes })
    if ($unknown.Count -gt 0) {
        throw "State has unsupported resources: $(($unknown.address) -join ', '). Update this checker before proceeding."
    }
    foreach ($type in $expectedTypes) {
        $matches = @($resources | Where-Object { $_.type -eq $type })
        if ($matches.Count -ne 1 -or -not $matches[0].values.id) {
            throw "Expected exactly one $type with an ID in state. Apply successfully before capturing."
        }
    }

    $items = @($resources | ForEach-Object {
        [PSCustomObject]@{ address = $_.address; type = $_.type; id = $_.values.id }
    })
    $inventoryData = [PSCustomObject]@{
        schema_version = 1
        account_id = $identity.Account
        captured_at_utc = (Get-Date).ToUniversalTime().ToString("o")
        resources = $items
    }
    $inventoryData | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Inventory -Encoding UTF8
    Write-Host "Captured $($items.Count) managed resources in $Inventory for AWS account $($identity.Account)."
    Write-Host ($items | Format-Table address, id -AutoSize | Out-String)
    Write-Host "This inventory excludes the separate state bucket, OIDC provider, budgets, and other unmanaged resources."
    return
}

if (-not (Test-Path -LiteralPath $Inventory -PathType Leaf)) {
    throw "Inventory not found: $Inventory. Capture it before destroying the site."
}
$inventoryData = Get-Content -LiteralPath $Inventory -Raw | ConvertFrom-Json
if ($inventoryData.schema_version -ne 1 -or -not $inventoryData.resources) {
    throw "Invalid or unsupported inventory."
}
if ($inventoryData.account_id -ne $identity.Account) {
    throw "Inventory account $($inventoryData.account_id) does not match the current AWS account $($identity.Account)."
}

function Get-InventoryId {
    param([string]$Type)
    $matches = @($inventoryData.resources | Where-Object { $_.type -eq $Type })
    if ($matches.Count -ne 1 -or -not $matches[0].id) {
        throw "Inventory must contain exactly one $Type with an ID."
    }
    return $matches[0].id
}

$bucket = Get-InventoryId "aws_s3_bucket"
$distribution = Get-InventoryId "aws_cloudfront_distribution"
$origin = Get-InventoryId "aws_cloudfront_origin_access_control"
$headers = Get-InventoryId "aws_cloudfront_response_headers_policy"
$role = Get-InventoryId "aws_iam_role"
$health = Get-InventoryId "aws_route53_health_check"
$topic = Get-InventoryId "aws_sns_topic"
$alarm = Get-InventoryId "aws_cloudwatch_metric_alarm"

# List operations distinguish an absent resource from an access-denied error.
$buckets = Get-AwsJson @("s3api", "list-buckets")
$distributions = Get-AwsJson @("cloudfront", "list-distributions")
$origins = Get-AwsJson @("cloudfront", "list-origin-access-controls")
$policies = Get-AwsJson @("cloudfront", "list-response-headers-policies", "--type", "custom")
$roles = Get-AwsJson @("iam", "list-roles")
$healthChecks = Get-AwsJson @("route53", "list-health-checks")
$topics = Get-AwsJson @("sns", "list-topics")
$subscriptions = Get-AwsJson @("sns", "list-subscriptions")
$alarms = Get-AwsJson @("cloudwatch", "describe-alarms")

$checks = @(
    [PSCustomObject]@{ Name = "Website bucket (including its settings and objects)"; Id = $bucket; Found = @($buckets.Buckets | Where-Object { $_.Name -eq $bucket }).Count -gt 0 }
    [PSCustomObject]@{ Name = "CloudFront distribution"; Id = $distribution; Found = @($distributions.DistributionList.Items | Where-Object { $_.Id -eq $distribution }).Count -gt 0 }
    [PSCustomObject]@{ Name = "CloudFront origin access control"; Id = $origin; Found = @($origins.OriginAccessControlList.Items | Where-Object { $_.Id -eq $origin }).Count -gt 0 }
    [PSCustomObject]@{ Name = "CloudFront response headers policy"; Id = $headers; Found = @($policies.ResponseHeadersPolicyList.Items | Where-Object { $_.ResponseHeadersPolicy.Id -eq $headers }).Count -gt 0 }
    [PSCustomObject]@{ Name = "GitHub deployment role (including inline policy)"; Id = $role; Found = @($roles.Roles | Where-Object { $_.RoleName -eq $role }).Count -gt 0 }
    [PSCustomObject]@{ Name = "Route 53 health check"; Id = $health; Found = @($healthChecks.HealthChecks | Where-Object { $_.Id -eq $health }).Count -gt 0 }
    [PSCustomObject]@{ Name = "SNS topic"; Id = $topic; Found = @($topics.Topics | Where-Object { $_.TopicArn -eq $topic }).Count -gt 0 }
    [PSCustomObject]@{ Name = "SNS subscriptions for topic"; Id = $topic; Found = @($subscriptions.Subscriptions | Where-Object { $_.TopicArn -eq $topic }).Count -gt 0 }
    [PSCustomObject]@{ Name = "CloudWatch alarm"; Id = $alarm; Found = @($alarms.MetricAlarms | Where-Object { $_.AlarmName -eq $alarm }).Count -gt 0 }
)

foreach ($check in $checks) {
    $status = if ($check.Found) { "REMAINS" } else { "NOT FOUND" }
    Write-Host "[$status] $($check.Name): $($check.Id)"
}
Write-Host "[REVIEW] State bucket, state versions, OIDC provider, budgets, and other resources outside this inventory must be reviewed separately."
if (@($checks | Where-Object { $_.Found }).Count -gt 0) {
    throw "One or more inventoried resources remain. Teardown is not complete."
}
Write-Host "All inventoried resource parents were absent in AWS account $($identity.Account)."
