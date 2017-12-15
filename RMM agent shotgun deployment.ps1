Param(
    # The organization's ID that you've defined in Kaseya (System > Orgs/Groups/Depts/Staff > Manage)
    [Parameter(Mandatory = $True, Position = 0)]
    [string]$organizationID, 

    # Options: Servers, Workstations, Both, All (both and all are the same)
    [Parameter(Mandatory = $True, Position = 1)]
    [string]$scope 
)

<# --------------------------------------------------------------------------------------------------------------
RMM agent shotgun deployment
Version: 0.0.1
Made by: Witt Allen
Objective: Remotely install the designated Kaseya agent on computers that have recently contacted the Domain Controller

DEPENDANCIES & ASSUMPTIONS:
- Script will be ran as Administrator
- Script will be ran on a Domain Controller
- OS is Windows Server 2008 or higher (PsExec req.)
- Imported modules are supported on Server's OS
- Server has .NET installed
- Depends on 'psexec' PowerShell module   -------------- Maybe not


GENERAL TODO:
- Create event log entries when stuff happens
# --------------------------------------------------------------------------------------------------------------
#>

# ------------------------------- Query AD for PCs that connected in last 30 days and write to file-------------------------------
# TODO: Test each string case, may not operate as expected
$scope = $scope.ToLower()
$daysAgo = (Get-Date).AddDays(-30)
$listPath = "C:\temp\ComputerList.txt"
$listPath2 = "C:\temp\ComputerList2.txt"

if (!(Test-Path "C:\temp\")) {
    New-Item "C:\temp\" -ItemType Directory
}

# TODO: Check for existence of $listPath
if ($scope -like "*server*") {
    $dcs = Get-ADComputer -Filter { (lastLogonDate -gt $daysAgo) -and (OperatingSystem -Like '*Server*')} -Properties lastLogonDate

    foreach ($dc in $dcs) { 
        Get-ADComputer $dc.Name -Properties lastlogontimestamp | 
            Select-Object @{n = "Computer"; e = {$_.Name}} |
            Out-File -FilePath $listPath -Encoding default -Append
    }
}
elseif ($scope -like "*workstation*") {
    $dcs = Get-ADComputer -Filter { (lastLogonDate -gt $daysAgo) -and (OperatingSystem -NotLike '*Server*')} -Properties lastLogonDate

    foreach ($dc in $dcs) { 
        Get-ADComputer $dc.Name -Properties lastlogontimestamp | 
            Select-Object @{n = "Computer"; e = {$_.Name}} |
            Out-File -FilePath $listPath -Encoding default -Append
    }
}
elseif (($scope -like "*both*") -or ($scope -like "*all*")) {
    $dcs = Get-ADComputer -Filter {lastLogonDate -gt $daysAgo} -Properties lastLogonDate

    foreach ($dc in $dcs) { 
        Get-ADComputer $dc.Name -Properties lastlogontimestamp | 
            Select-Object @{n = "Computer"; e = {$_.Name}} |
            Out-File -FilePath $listPath -Encoding default -Append
    }
}
else {
    # TODO: Exit script with failure code
}

$file = Get-Content $listPath
# Reduce file to just computer names
foreach ($line in $file) {
    if (($line -eq "") -or ($line -like "*Computer*") -or ($line -like "*----*")) {
        # Do nothing
    }
    else {
        $line | Out-File -FilePath $listPath2 -Encoding default -append
    }
}

# ------------------------------------- Remove whitespace
$content = Get-Content $listPath2
$content | Foreach {$_.TrimEnd()} | Set-Content $listPath

# ------------------------------------- Download RMM agent
Write-Host "Downloading RMM agent - " (Get-Date).ToShortTimeString()
$vsaURL = "https://vsa.data-blue.com"
$agentEXE = "KcsSetup.exe"
$agentSwitches = "/s /j /e /g=root." + $organizationID + " /c" # Switches: http://help.kaseya.com/WebHelp/EN/VSA/9040000/#493.htm
$url = $vsaURL + "/install/VSA-default--1/" + $agentEXE
$output = "C:\temp\$agentEXE"
$wc = New-Object System.Net.WebClient
$wc.DownloadFile($url, $output) 

# ------------------------------------- Download PsExec
Write-Host "Downloading PsTools - " (Get-Date).ToShortTimeString()
$timeout = 5 # Seconds for psexec to spend attempting to connect to remote PC
$url = "https://download.sysinternals.com/files/PSTools.zip"
$psToolsZip = "C:\temp\PSTools.zip"
$psToolsPath = "C:\temp\PSTools\"
$psExecPath = "C:\temp\PSTools\psexec.exe"
$wc = New-Object System.Net.WebClient
$wc.DownloadFile($url, $psToolsZip)     

# ------------------------------------- Unzip the PSTools package
Write-Host "Unzipping PSTools - " (Get-Date).ToShortTimeString()
# Source: https://stackoverflow.com/questions/27768303/how-to-unzip-a-file-in-powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Unzip {
    param([string]$zipfile, [string]$outpath)

    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipfile, $outpath)
}

Unzip $psToolsZip $psToolsPath

# ------------------------------------- Move to sys32 so it can be used in cmd prompt
Move-Item $psExecPath "C:\Windows\System32\psexec.exe"

# ------------------------------------- Run psexec and pipe file to it
& psexec @$listPath -c -v -n $timeout -s -accepteula cmd "C:\temp\$agentEXE"$agentSwitches

<#
Start-Process -Wait `
    -PSPath $psExecPath -ArgumentList "@$listPath2 -c -v -n $timeout -accepteula cmd C:\temp\$agentEXE$agentSwitches" `
    -RedirectStandardError c:\temp\error.log -RedirectStandardOutput c:\temp\output.log

$output = cmd /s /c "psexec.exe @$listPath2 -c -v -n $timeout -accepteula cmd C:\temp\$agentEXE$agentSwitches 2>&1"
#>

# ------------------------------------- CLEANUP -------------------------------------
Write-Host "Cleaning up - " (Get-Date).ToShortTimeString()
# Delete Temp folder 
Move-Item "C:\Windows\System32\psexec.exe" $psExecPath
Remove-Item "C:\temp\*" -Recurse -Verbose -Force

# ------------------------------------- End of Script -------------------------------------
Write-Host "End of script - " (Get-Date).ToShortTimeString()