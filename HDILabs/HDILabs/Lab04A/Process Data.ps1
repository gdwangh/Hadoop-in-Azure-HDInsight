$clusterName = "clusterLab4"
$storageAccountName = "hdstores"
$containerName = "hdfiles"

$sqlDatabaseServerName = "prmp7xooid"
$sqlDatabaseUserName = "wanghsql"
$sqlDatabasePassword = "Wangh789"
$sqlDatabaseDatabaseName = "AnalysisDB"
$tableName = "weather"

$thisfolder = Split-Path -parent $MyInvocation.MyCommand.Definition
$storageAccountKey = (Get-AzureStorageKey -StorageAccountName $storageAccountName).Primary
$blobContext = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey

# Remove output from previous execution
Get-AzureStorageBlob -Container $containerName -blob *data/temp* -Context $blobContext | ForEach-Object {Remove-AzureStorageBlob -Blob $_.Name -Container $containerName -Context $blobContext}

# Upload source data
$localfile = "$thisfolder\Source.txt"
$destBlob = "data/temp/source/source.txt"
Set-AzureStorageBlobContent -File $localFile -Container $containerName -Blob $destBlob -Context $blobContext -Force

# Perform initial processing with Pig
$destfolder = "data/temp"
$scriptFile = "Pig.txt"
$destBlob = "$destfolder/$scriptFile"
$filename = "$thisfolder\$scriptFile"
Set-AzureStorageBlobContent -File $filename -Container $containerName -Blob $destBlob -Context $blobContext -Force
$jobDef = New-AzureHDInsightPigJobDefinition -File "wasb:///$destfolder/$scriptFile"
$pigJob = Start-AzureHDInsightJob -Cluster $clusterName -JobDefinition $jobDef
Write-Host "Pig job submitted..."
Wait-AzureHDInsightJob -Job $pigJob -WaitTimeoutInSeconds 3600
Get-AzureHDInsightJobOutput -Cluster $clusterName -JobId $pigJob.JobId -StandardError

# Perform further processing with Hive
$scriptFile = "Hive.txt"
$destBlob = "$destfolder/$scriptFile"
$filename = "$thisfolder\$scriptFile"
Set-AzureStorageBlobContent -File $filename -Container $containerName -Blob $destBlob -Context $blobContext -Force
$jobDef = New-AzureHDInsightHiveJobDefinition -File "wasb:///$destBlob"
$hiveJob = Start-AzureHDInsightJob -Cluster $clusterName -JobDefinition $jobDef
Write-Host "Hive job submitted..."
Wait-AzureHDInsightJob -Job $hiveJob -WaitTimeoutInSeconds 3600
Get-AzureHDInsightJobOutput -Cluster $clusterName -JobId $hiveJob.JobId -StandardError

#Create a Sqoop job
$outputPath = "$destfolder/hivetable"
$sqoopCommand = "export --connect jdbc:sqlserver://$sqlDatabaseServerName.database.chinacloudapi.cn;user=$sqlDatabaseUserName@$sqlDatabaseServerName;password=$sqlDatabasePassword;database=$sqlDatabaseDatabaseName"
$sqoopCommand += " --table $tableName --export-dir /$outputPath --input-fields-terminated-by \t --input-null-non-string \\N -m 16"
$sqoopDef = New-AzureHDInsightSqoopJobDefinition -Command $sqoopCommand

# Submit the Sqoop job
$sqoopJob = Start-AzureHDInsightJob -Cluster $clusterName -JobDefinition $sqoopDef
Write-Host "Sqoop job submitted..."
Wait-AzureHDInsightJob -WaitTimeoutInSeconds 3600 -Job $sqoopJob
Get-AzureHDInsightJobOutput -Cluster $clusterName -JobId $sqoopJob.JobId -StandardError