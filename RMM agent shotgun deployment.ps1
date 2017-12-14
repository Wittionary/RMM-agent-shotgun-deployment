Param(
    # Options: Servers, Workstations, Both, All (both and all are the same)
    [Parameter(Mandatory = $True, Position = 0)]
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


<# ---------------------------------------- This comment block can be removed if still commented out at production
$repoURL = "https://github.com/replicaJunction/PsExec/blob/master/PsExec/PsExec.psm1"
$repoPath =
$tempPath = "C:\temp"

# Install module to assist with psexec handling
# https://www.powershellgallery.com/packages/psexec/0.0.7
# https://github.com/replicaJunction/PsExec
if (Install-Module -Name psexec -RequiredVersion 0.0.7) {
    # Do nothing
}
else {
       # SOURCE: https://github.com/MSAdministrator/GetGithubRepository
       # .Synopsis
       # This function will download a Github Repository without using Git
       # .DESCRIPTION
       # This function will download files from Github without using Git.  You will need to know the Owner, Repository name, branch (default master),
       # and FilePath.  The Filepath will include any folders and files that you want to download.
       # .EXAMPLE
       # Get-GithubRepository -Owner MSAdministrator -Repository WriteLogEntry -Verbose -FilePath `
       #         'WriteLogEntry.psm1',
       #         'WriteLogEntry.psd1',
       #         'Public',
       #         'en-US',
       #         'en-US\about_WriteLogEntry.help.txt',
       #         'Public\Write-LogEntry.ps1'
        
    function Get-GithubRepository {
        [CmdletBinding()]
        [Alias()]
        [OutputType([int])]
        Param
        (
            # Please provide the repository owner
            [Parameter(Mandatory = $true,
                ValueFromPipelineByPropertyName = $true,
                Position = 0)]
            [string]$Owner,

            # Please provide the name of the repository
            [Parameter(Mandatory = $true,
                ValueFromPipelineByPropertyName = $true,
                Position = 1)]
            [string]$Repository,

            # Please provide a branch to download from
            [Parameter(Mandatory = $false,
                ValueFromPipelineByPropertyName = $true,
                Position = 2)]
            [string]$Branch = 'master',

            # Please provide a list of files/paths to download
            [Parameter(Mandatory = $true,
                ValueFromPipelineByPropertyName = $true,
                Position = 3)]
            [string[]]$FilePath
        )
        Begin {
            $modulespath = ($env:psmodulepath -split ";")[0]            
            $PowerShellModule = "$modulespath\$Repository"
            Write-Verbose "Creating module directory"
            New-Item -Type Container -Force -Path $PowerShellModule | out-null
            Write-Verbose "Downloading and installing"
            $wc = New-Object System.Net.WebClient
            $wc.Encoding = [System.Text.Encoding]::UTF8
        }
        Process {
            foreach ($item in $FilePath) {
                Write-Verbose -Message "$item in FilePath"

                if ($item -like '*.*') {
                    Write-Debug -Message "Attempting to create $PowerShellModule\$item"
                    New-Item -ItemType File -Force -Path "$PowerShellModule\$item" | Out-Null
                    $url = "https://raw.githubusercontent.com/$Owner/$Repository/$Branch/$item"
                    Write-Debug -Message "Attempting to download from $url"
                    ($wc.DownloadString("$url")) | Out-File "$PowerShellModule\$item"
                }
                else {
                    Write-Debug -Message "Attempting to create $PowerShellModule\$item"
                    New-Item -ItemType Container -Force -Path "$PowerShellModule\$item" | Out-Null
                    $url = "https://raw.githubusercontent.com/$Owner/$Repository/$Branch/$item"
                    Write-Debug -Message "Attempting to download from $url"
                }
            }
        }
        End {
        }
    }

    Get-GithubRepository -Owner replicaJunction -Repository PsExec -Verbose -FilePath `
        'Build',
            'Build\AppVeyor.ps1',
            'Build\deploy.psdeploy.ps1',
            'Build\psake.ps1',
        'PsExec',
            'PsExec\Public',
                'PsExec\Public\Get-PsExec.ps1',
                'PsExec\Public\Invoke-PsExec.ps1',
            'PsExec\PsExec.psd1',
            'PsExec\PsExec.psm1',
        'Tests',
            'Tests\PsExec.Tests.ps1',
        'LICENSE',
        'README.md',
        'appveyor.yml'    
    Import-Module $repoPath
}
#>

# ------------------------------- Query AD for PCs that connected in last 30 days and write to file-------------------------------
# TODO: Test each string case, may not operate as expected
$scope = $scope.ToLower()
$daysAgo = (Get-Date).AddDays(-30)
$listPath = "C:\temp\ComputerList.txt"

if ($scope -like "*server*") {
    $dcs = Get-ADComputer -Filter { (lastLogonDate -gt $daysAgo) -and (OperatingSystem -Like '*Server*')} -Properties lastLogonDate

    foreach ($dc in $dcs) { 
        Get-ADComputer $dc.Name -Properties lastlogontimestamp | 
            Select-Object @{n = "Computer"; e = {$_.Name}}, @{Name = "Lastlogon"; Expression = {[DateTime]::FromFileTime($_.lastLogonTimestamp)}} |
            Out-File -FilePath $listPath -Append
    }
}
elseif ($scope -like "*workstation*") {
    $dcs = Get-ADComputer -Filter { (lastLogonDate -gt $daysAgo) -and (OperatingSystem -NotLike '*Server*')} -Properties lastLogonDate

    foreach ($dc in $dcs) { 
        Get-ADComputer $dc.Name -Properties lastlogontimestamp | 
            Select-Object @{n = "Computer"; e = {$_.Name}}, @{Name = "Lastlogon"; Expression = {[DateTime]::FromFileTime($_.lastLogonTimestamp)}} |
            Out-File -FilePath $listPath -Append
    }
}
elseif (($scope -like "*both*") -or ($scope -like "*all*")) {
    $dcs = Get-ADComputer -Filter {lastLogonDate -gt $daysAgo} -Properties lastLogonDate

    foreach ($dc in $dcs) { 
        Get-ADComputer $dc.Name -Properties lastlogontimestamp | 
            Select-Object @{n = "Computer"; e = {$_.Name}}, @{Name = "Lastlogon"; Expression = {[DateTime]::FromFileTime($_.lastLogonTimestamp)}} |
            Out-File -FilePath $listPath -Append
    }
}
else {
    # TODO: Exit script with failure code
}

# ------------------------------------- Download RMM agent
$vsaURL = "https://vsa.data-blue.com"
$agentEXE = "KcsSetup.exe"
$agentSwitches = " /e /g=root." + $organizationID + " /c /j /s" # Switches: http://help.kaseya.com/WebHelp/EN/VSA/9040000/#493.htm
$url = $vsaURL + "/install/VSA-default--1/" + $agentEXE
$output = "C:\$agentEXE"
$wc = New-Object System.Net.WebClient
$wc.DownloadFile($url, $output) 

# ------------------------------------- Download PsExec
$timeout = 5 # Seconds for psexec to spend attempting to connect to remote PC
$url = "https://download.sysinternals.com/files/PSTools.zip"
$psToolsZip = "C:\temp\PSTools.zip"
$psToolsPath = "C:\temp\PSTools\"
$psExecPath = "C:\temp\PSTools\psexec.exe"
$wc = New-Object System.Net.WebClient
$wc.DownloadFile($url, $psToolsZip)     

# Unzip the PSTools package
# Source: https://stackoverflow.com/questions/27768303/how-to-unzip-a-file-in-powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Unzip {
    param([string]$zipfile, [string]$outpath)

    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipfile, $outpath)
}

Unzip $psToolsZip $psToolsPath

# Move to sys32 so it can be used in cmd prompt
Move-Item $psExecPath "C:\Windows\System32\psexec.exe"

# Run psexec and pipe file to it
& psexec -c KcsSetup.exe -n $timeout -s -v @file $listPath

# Delete Temp folder 
Move-Item "C:\Windows\System32\psexec.exe" $psExecPath