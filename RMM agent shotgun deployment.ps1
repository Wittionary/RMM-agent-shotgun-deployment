<# --------------------------------------------------------------------------------------------------------------
RMM agent shotgun deployment
Version: 0.0.1
Made by: Witt Allen
Objective: Remotely install the designated Kaseya agent on computers that have recently contacted the Domain Controller

DEPENDANCIES & ASSUMPTIONS:
- Script will be ran as Administrator
- Script will be ran on a Domain Controller
- Server's OS can use WMI filtering
- Imported modules are supported on Server's OS
- Server has .NET installed
- Depends on 'psexec' PowerShell module

GENERAL TODO:
- Create event log entries when stuff happens
# --------------------------------------------------------------------------------------------------------------
#>

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
       <# SOURCE: https://github.com/MSAdministrator/GetGithubRepository
        .Synopsis
        This function will download a Github Repository without using Git
        .DESCRIPTION
        This function will download files from Github without using Git.  You will need to know the Owner, Repository name, branch (default master),
        and FilePath.  The Filepath will include any folders and files that you want to download.
        .EXAMPLE
        Get-GithubRepository -Owner MSAdministrator -Repository WriteLogEntry -Verbose -FilePath `
                'WriteLogEntry.psm1',
                'WriteLogEntry.psd1',
                'Public',
                'en-US',
                'en-US\about_WriteLogEntry.help.txt',
                'Public\Write-LogEntry.ps1'
        #>
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


