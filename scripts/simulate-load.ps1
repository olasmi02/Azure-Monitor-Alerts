<#
.SYNOPSIS
    Simulates transaction load on the Storage Account to trigger the Metric Alert rule.
.DESCRIPTION
    This script creates a temporary test container and uploads 100 mock files in a loop
    using Azure CLI. This generates over 100 write transactions in a short window, which
    exceeds the 50-transactions-per-minute threshold and fires the alert.
.PARAMETER ResourceGroupName
    The Resource Group containing the storage account (default: 'rg-alerts-demo').
.PARAMETER StorageAccountName
    The name of the Storage Account to load test (Required).
.EXAMPLE
    .\simulate-load.ps1 -StorageAccountName "alertstore49821"
#>

[CmdletBinding()]
param (
    [string]$ResourceGroupName = "rg-alerts-demo",

    [Parameter(Mandatory = $true)]
    [string]$StorageAccountName
)

# Ensure CLI is available
$azCheck = Get-Command az -ErrorAction SilentlyContinue
if ($null -eq $azCheck) {
    Write-Error "Azure CLI (az) is not installed."
    exit 1
}

Write-Host "Retrieving connection string for Storage Account '$StorageAccountName'..." -ForegroundColor Cyan
$connString = az storage account show-connection-string --name $StorageAccountName --resource-group $ResourceGroupName --query connectionString -o tsv 2>$null

if ([string]::IsNullOrEmpty($connString)) {
    Write-Error "Could not retrieve connection string. Check Storage Account name and Resource Group."
    exit 1
}

$containerName = "loadtestcontainer"
Write-Host "Creating test container '$containerName'..." -ForegroundColor Cyan
$null = az storage container create --name $containerName --connection-string $connString --output json

# Create a small temp file to upload
$tempFile = Join-Path $env:TEMP "load-sim-test-file.txt"
"Observability and Alerts Load Simulation Data - " + (Get-Date).ToString() | Out-File -FilePath $tempFile -Encoding utf8

Write-Host "--------------------------------------------------" -ForegroundColor Gray
Write-Host "Starting simulation loop: performing 120 blob uploads..." -ForegroundColor Yellow
Write-Host "This will exceed the threshold of 50 transactions/minute." -ForegroundColor Yellow
Write-Host "--------------------------------------------------" -ForegroundColor Gray

$startTime = Get-Date

for ($i = 1; $i -le 120; $i++) {
    $blobName = "testblob-$i"
    # Upload blob
    $upload = az storage blob upload --container-name $containerName --file $tempFile --name $blobName --connection-string $connString --no-progress --output json 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [$i/120] Successfully uploaded $blobName" -ForegroundColor Green
    } else {
        Write-Warning "  [$i/120] Upload failed for $blobName"
    }
    # Dynamic pause to distribute load slightly, but stay fast enough to trigger within 1 minute
    Start-Sleep -Milliseconds 100
}

$duration = (Get-Date) - $startTime
Write-Host "--------------------------------------------------" -ForegroundColor Gray
Write-Host "Load simulation complete! Total time: $($duration.TotalSeconds) seconds." -ForegroundColor Green
Write-Host "Cleaning up test container..." -ForegroundColor Cyan
$null = az storage container delete --name $containerName --connection-string $connString --yes --output json

# Clean up local file
if (Test-Path $tempFile) { Remove-Item $tempFile }

Write-Host "Cleanup complete." -ForegroundColor Green
Write-Host "`n>>> ACTION REQUIRED: Wait 3-5 minutes for Azure Monitor to evaluate metrics and fire the alert. You should receive an email notification shortly." -ForegroundColor Yellow
