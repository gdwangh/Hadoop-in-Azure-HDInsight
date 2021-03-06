$clusterName = "clusterLab4"
$storageAccountName = "hdstores"
$containerName = "hdfiles"
$hdUser = "gdwhHD"
$hdPassword = "Wangh123!@#"

$sqlServer = "prmp7xooid"
$sqlLogin = "wanghsql"
$sqlPassword = "Wangh789"
$sqlDB = "AnalysisDB"
$sqlTable = "logdata"

# Prepare SQL database (drop and recreate table)
Write-Host "Creating $sqlTable table in Azure SQL Database $sqlDB..."
$sqlCmd = @"
IF EXISTS (SELECT * FROM sys.tables WHERE name = '$sqlTable') DROP TABLE $sqlTable;
CREATE TABLE $sqlTable
(log_date date PRIMARY KEY CLUSTERED,
 Requests int,
 InboundBytes int,
 OutboundBytes int);
"@
$conn = New-Object System.Data.SqlClient.SqlConnection
$Conn.ConnectionString = "Data Source=$sqlServer.database.chinacloudapi.cn;Initial Catalog=$sqlDB;User ID=$sqlLogin; Password=$sqlPassword; Encrypt=true; Trusted_Connection=false;"
$conn.Open()
$cmd = New-Object System.Data.SqlClient.SqlCommand
$cmd.Connection = $conn
$cmd.CommandText = $sqlCmd
$cmd.ExecuteNonQuery()
$conn.Close()

# Create storage context
$thisfolder = Split-Path -parent $MyInvocation.MyCommand.Definition
$storageAccountKey = Get-AzureStorageKey $storageAccountName | %{ $_.Primary }
$destContext = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey
$destfolder = "data/iislogs"

# Upload source log files
$localFolder = "$thisfolder\iislogs_gz"
$files = Get-ChildItem $localFolder
foreach($file in $files){
  $fileName = "$localFolder\$file"
  $blobName = "$destfolder/stagedlogs/$file"
  Set-AzureStorageBlobContent -File $filename -Container $containerName -Blob $blobName -Context $destContext -Force
}

# Upload Oozie workflow files
$localFolder = "$thisfolder\oozieworkflow"
$files = Get-ChildItem $localFolder
foreach($file in $files){
  $fileName = "$localFolder\$file"
  $blobName = "$destfolder/oozieworkflow/$file"
  Set-AzureStorageBlobContent -File $filename -Container $containerName -Blob $blobName -Context $destContext -Force
}

# set Oozie job configuration
$oozieConfig = @"
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
   <property>
       <name>nameNode</name>
       <value>wasb://$containerName@$storageAccountName.blob.core.chinacloudapi.cn</value>
   </property>
   <property>
       <name>jobTracker</name>
       <value>jobtrackerhost:9010</value>
   </property>
   <property>
       <name>queueName</name>
       <value>default</value>
   </property>
   <property>
       <name>oozie.use.system.libpath</name>
       <value>true</value>
   </property>
   <property>
       <name>DropTableScript</name>
       <value>DropHiveTables.txt</value>
   </property>
   <property>
       <name>CleanseDataScript</name>
       <value>CleanseData.txt</value>
   </property>
   <property>
       <name>CreateTableScript</name>
       <value>CreateHiveTables.txt</value>
   </property>
   <property>
       <name>SummarizeDataScript</name>
       <value>SummarizeData.txt</value>
   </property>
   <property>
       <name>stagingFolder</name>
       <value>/$destfolder/stagedlogs</value>
   </property>
   <property>
       <name>cleansedTable</name>
       <value>cleansedlogs</value>
   </property>
   <property>
       <name>cleansedFolder</name>
       <value>/$destfolder/cleansedlogs</value>
   </property>
   <property>
       <name>summaryTable</name>
       <value>summarizedlogs</value>
   </property>
   <property>
       <name>summaryFolder</name>
       <value>/$destfolder/summarizedlogs</value>
   </property>
   <property>
       <name>sqlConnectionString</name>
       <value>"jdbc:sqlserver://$sqlServer.database.chinacloudapi.cn;user=$sqlLogin@$sqlServer;password=$sqlPassword;database=$sqlDB"</value>
   </property>
   <property>
       <name>sqlTable</name>
       <value>$sqlTable</value>
   </property>
   <property>
       <name>sourceDir</name>
       <value>/$destfolder/summarizedlogs</value>
   </property>
   <property>
       <name>user.name</name>
       <value>$hdUser</value>
   </property>
   <property>
       <name>oozie.wf.application.path</name>
       <value>/$destfolder/oozieworkflow</value>
   </property>
</configuration>
"@

# Initiate Oozie job
$password = ConvertTo-SecureString $hdPassword -AsPlainText -Force
$creds = New-Object System.Management.Automation.PSCredential ($hdUser, $password)
$oozieJobs = "https://$clusterName.azurehdinsight.cn:443/oozie/v2/jobs"
$jobResponse = Invoke-RestMethod -Method Post -Uri $oozieJobs -Credential $creds -Body $oozieConfig -ContentType "application/xml" -OutVariable $oozieJob
$jsonResponse = ConvertFrom-Json (ConvertTo-Json -InputObject $jobResponse)
$oozieJobId = $jsonResponse[0].("id")
Write-Host "Oozie job id is $oozieJobId"
$startOozieJob = "https://$clusterName.azurehdinsight.cn:443/oozie/v2/job/" + $oozieJobId + "?action=start"
$startResonse = Invoke-RestMethod -Method Put -Uri $startOozieJob -Credential $creds | Format-Table -HideTableHeaders
Write-Host "Oozie job submitted..."

# Wait for status
Start-Sleep -Seconds 30
$oozieStatus = "https://$clusterName.azurehdinsight.cn:443/oozie/v2/job/" + $oozieJobId + "?show=info"
$status = Invoke-RestMethod -Method Get -Uri $oozieStatus -Credential $creds 
$jsonStatus = ConvertFrom-Json (ConvertTo-Json -InputObject $status)
$JobStatus = $jsonStatus[0].("status")

while($JobStatus -notmatch "SUCCEEDED|KILLED")
{
    Start-Sleep -Seconds 30
    $status = Invoke-RestMethod -Method Get -Uri $oozieStatus -Credential $creds 
    $jsonStatus = ConvertFrom-Json (ConvertTo-Json -InputObject $status)
    $JobStatus = $jsonStatus[0].("status")
    Write-Host "$(Get-Date -format 'G'): $oozieJobId status: $JobStatus..."
}
if ($jobStatus -eq "SUCCEEDED")
{
  $color = "Green"
}
else
{
  $color = "Red"
}
Write-Host "$(Get-Date -format 'G'): $oozieJobId status: $JobStatus" -ForegroundColor $color