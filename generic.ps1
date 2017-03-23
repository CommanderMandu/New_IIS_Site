# --------------------------------------------------------------------
# IIS Web Site Creation Script
#
#
# --------------------------------------------------------------------


# --------------------------------------------------------------------
# Check Execution
# --------------------------------------------------------------------
Write-Host "Checking PowerShell execution policies" -ForegroundColor Yellow
$Policy = "RemoteSigned"
If ((get-ExecutionPolicy) -ne $Policy) {
	Write-Host "Script Execution is disabled. Enabling it now"
	Set-ExecutionPolicy $Policy -Force
	Write-Host "Please Re-run this script in a new PowerShell enviroment"
	Exit
}

# --------------------------------------------------------------------
# Force 64-bit PowerShell
# --------------------------------------------------------------------
Write-Host "Force 64-bit PowerShell" -ForegroundColor Yellow
if ($pshome -like "*syswow64*") {
 
	Write-Warning "Restarting script under 64 bit PowerShell"

	# relaunch this script under 64 bit shell
	# if you want powershell 2.0, add -version 2 *before* -file parameter
	& (join-path ($pshome -replace "syswow64", "sysnative") powershell.exe) -file `
	(join-path $psscriptroot $myinvocation.mycommand) @args

	# exit 32 bit script
	exit
}

# --------------------------------------------------------------------
# DEFINE GLOBAL VARIABLES
# --------------------------------------------------------------------
# Host(s): 	ESAPWN2AHV01 ESAPWN2AHV02
Write-Host "Defining global values" -ForegroundColor Yellow
$website_name = ""
$website_host_header = ""
$website_IP = "127.0.0.1"
$website_port = "8443"
$website_default_document = "default.htm"

# --------------------------------------------------------------------
# --------------------------------------------------------------------
# --------------------------------------------------------------------
$InetPubRoot = "c:\inetpub\wwwroot\PaychexImaging\PaychexImaging"
$InetPubLog = "l:\logs"
$NLBRoot = "w:\nlb"
# $website_IP = (Get-NetAdapter -name "Ethernet" | Get-NetIPAddress).IPv4Address
$website_source_directory = $InetPubRoot + "\" + $website_name
$website_virtual_directory = "IIS:\Sites\" + $website_name
$app_pool_name = $website_name
$app_pool_virtual_directory = "IIS:\AppPools\" + $app_pool_name
$log_directory = $InetPubLog + "\" + $website_name
$nlb_directory = $NLBRoot + "\" + $website_name
$nlb_virtual_directory = "IIS:\Sites\" + $website_name + "\nlb"
# $computerName = (Get-WmiObject win32_computersystem).name

# --------------------------------------------------------------------
# Load Feature Installation Modules
# --------------------------------------------------------------------
Import-Module WebAdministration -ErrorAction Stop

# Create Web site root directory
Write-Host "Creating Web site directory" -ForegroundColor Yellow
if((Test-Path $website_source_directory) -eq 0)
{
	New-Item -ItemType directory -Path "$website_source_directory"
}

# Create Log directory
Write-Host "Creating log directory" -ForegroundColor Yellow
if((Test-Path $log_directory) -eq 0)
{
	New-Item -ItemType directory -Path "$log_directory"
}

# Create NLB directory
Write-Host "Creating NLB directory" -ForegroundColor Yellow
if((Test-Path $nlb_directory) -eq 0)
{
	New-Item -ItemType directory -Path "$nlb_directory"
}

# Create Application Pool and set to .NET 4
Write-Host "Creating .NET 4 AppPool" -ForegroundColor Yellow
New-WebAppPool $app_pool_name -Force
Set-ItemProperty $app_pool_virtual_directory managedRuntimeVersion v4.0

# Create Web site
Write-Host "Creating new Web site" -ForegroundColor Yellow
New-Website -Name "$website_name" -PhysicalPath $website_source_directory -ApplicationPool "$app_pool_name" -HostHeader "$website_host_header" -IPAddress $website_IP -Port $website_port -Force

# Set default document
Write-Host "Setting default document" -ForegroundColor Yellow
if ((Get-WebConfiguration //defaultDocument/files/* "$website_virtual_directory" | where {$_.value} -eq $website_default_document).length -eq 0)
{
	Remove-WebconfigurationProperty //defaultDocument/files "$website_virtual_directory" -name collection -AtElement @{value=$website_default_document}
}
Add-WebConfiguration //defaultDocument/files "$website_virtual_directory" -atIndex 0 -Value @{value="$website_default_document"}

# Set permissions to allow NetworkService and IIS_IUSRS read and execute rights
Write-Host "Setting directory permissions" -ForegroundColor Yellow
$inherit = [system.security.accesscontrol.InheritanceFlags]"ContainerInherit, ObjectInherit"
$propagation = [system.security.accesscontrol.PropagationFlags]"None"

$acl = Get-Acl "$website_source_directory"
$accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("NetworkService", "ReadAndExecute", $inherit, $propagation, "Allow")
$acl.AddAccessRule($accessRule)

Set-Acl -aclobject $acl -path $website_source_directory

$accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("IIS_IUSRS", "ReadAndExecute", $inherit, $propagation, "Allow")
$acl.AddAccessRule($accessRule)

Set-Acl -aclobject $acl -path $website_source_directory

# Set logging properties
Write-Host "Setting logging properties" -ForegroundColor Yellow
$a = get-itemproperty $website_virtual_directory
$a.logFile.directory = "$log_directory"
$a.logFile.logExtFileFlags = "Date,Time,ClientIP,UserName,ComputerName,ServerIP,Method,UriStem,UriQuery,HttpStatus,BytesSent,BytesRecv,TimeTaken,ServerPort,UserAgent,Cookie,Referer,Host,ProtocolVersion"
$a | set-item

# Create NLB virtual directory
Write-Host "Create NLB virtual directory" -ForegroundColor Yellow
New-Item $nlb_virtual_directory -type VirtualDirectory -physicalPath $nlb_directory