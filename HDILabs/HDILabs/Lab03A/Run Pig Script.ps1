$clusterName = "clusterHive"
$storageAccountName = "hdstores"
$containerName = "hdfiles"

$thisfolder = Split-Path -parent $MyInvocation.MyCommand.Definition
$storageAccountKey = (Get-AzureStorageKey -StorageAccountName $storageAccountName).Primary
$blobContext = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey

# Remove output from previous execution
Get-AzureStorageBlob -Container $containerName -blob *data/*weather* -Context $blobContext | ForEach-Object {Remove-AzureStorageBlob -Blob $_.Name -Container $containerName -Context $blobContext}

# Upload source data
$localfile = "$thisfolder\heathrow.txt"
$destBlob = "data/weather/heathrow.txt"
Set-AzureStorageBlobContent -File $localFile -Container $containerName -Blob $destBlob -Context $blobContext -Force

# Upload Pig Latin script
$destfolder = "data"
$scriptFile = "scrubweather.pig"
$destBlob = "$destfolder/$scriptFile"
$filename = "$thisfolder\$scriptFile"
Set-AzureStorageBlobContent -File $filename -Container $containerName -Blob $destBlob -Context $blobContext -Force

# Run the Pig job
$jobDef = New-AzureHDInsightPigJobDefinition -File "wasb:///$destfolder/$scriptFile"
$pigJob = Start-AzureHDInsightJob -Cluster $clusterName -JobDefinition $jobDef
Write-Host "Pig job submitted..."
Wait-AzureHDInsightJob -Job $pigJob -WaitTimeoutInSeconds 3600
Get-AzureHDInsightJobOutput -Cluster $clusterName -JobId $pigJob.JobId -StandardError
