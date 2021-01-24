# RNDR Watchdog (Dual Use Version)
# Filename: RNDR_Watchdog_DualUse.ps1

$Release = "v0.2.1"

# This Windows Powershell script ensures the RenderToken RNDRclient.exe (RNDR) is running at all time and allows to start/shutdown an alternative workload (Dual) when the client signals it is idle.
# The RNDR client won't process any job if the GPUs are under load or VRAM is used, therefore the Dual workload needs to be shut down completely before rendering.
#
# DISCLAIMER: This is a community solution. No official RNDR project team support is provided by for this script. If you prefer stability the team recommends not to use any custom scripts at all.
# DISCLAIMER: RNDR client runtime does not equal rendertime. The measured runtime includes all overhead for download/load/save/upload as well as failed jobs etc.
#
# Keep this file in the same folder as the client rndrclient.exe
# Edit the user config file RNDRstart_Userconfig.ini before launching.
#
# This project has been implemented using T-Rex crypto mining software and crypto mining pool Ethermine. See https://ethermine.org/start for downloads and configuration.
#
# If you have issues launching this script or if you want to use it with Windows Autostart please create a file named RNDR_Watchdog_START.bat with the following line as content:
# START powershell.exe -ExecutionPolicy Bypass -File "RNDR_Watchdog_DualUse.ps1"
#
# Render on!


# Set working directory
Set-Location -Path $PSScriptRoot
$currentPath = $PSScriptRoot

# Temporary value. Logfile name will get overwritten by user config
$logFile = "$currentPath\RNDR_Watchdog.log"

# Main function to launch the RNDR client
Function Launch-RNDR-Client {

    # Check if RNDR Client is running. 
    $RNDRProcesses = Get-Process -Name $RNDRProcessName -ErrorAction SilentlyContinue
    if ($RNDRProcesses -eq $null)
    {
        # Restart if not.
        # Set overclocking profile to RNDR
        If ($UseOverclocking)
        {
            Start-Process -WindowStyle Minimized $OverclockingApp $OverclockingCommandRNDR
            Add-Logfile-Entry "Overclocking set to $OverclockingCommandRNDR."
        }

        Write-Host (Get-Date) : RNDR client application launched.

        if (Test-Path $RNDRClientLaunchCommand) 
        {
            Start-Process $RNDRClientLaunchCommand -WindowStyle Minimized
        }
        else
        {
            Add-Logfile-Entry "Cannot start RNDR because file does not exist. Please configure RNDRLauchCommand in watchdog correctly. $RNDRClientLaunchCommand"
            Write-Host  -ForegroundColor Red (Get-Date) : Cannot start RNDR because file does not exist. 
            Write-Host (Get-Date) : Please configure RNDRLauchCommand in watchdog correctly. $RNDRClientLaunchCommand
        }

        $global:RNDRStartDate = Get-Date

        # Set state to all processes responding
        $global:RNDRNotRespondedSince = $null
 
        # Wait
        Start-Sleep -Seconds $sleepRNDRWarmup
   
    }
}


# Watchdog function to make sure RNDR is running at all time
Function Keep-RNDR-Client-Running {
    
    # Check if RNDR Client is running. Restart if not. The actual Watchdog.
    $RNDRProcesses = Get-Process -Name $RNDRProcessName -ErrorAction SilentlyContinue
    
    if ($RNDRProcesses -eq $null)
    {

        Write-Host -ForegroundColor Red (Get-Date): RNDR client is not running. Restarting now.

        # Write to log file
        Add-Logfile-Entry "RNDR client is not running. Restarting now. See for more information $RNDRClientLogs" 

        # Manually set the flag in Windows Registry to IDLE. In case the client has issues to start up the node can work on Dual during that time.
        Set-ItemProperty -Path Registry::HKEY_CURRENT_USER\SOFTWARE\OTOY -Name RNDR_IDLE -errorAction SilentlyContinue -Value 1

        $global:RNDRRestarts = $global:RNDRRestarts + 1

        # Start client
        Launch-RNDR-Client

    } 
    else 
    { 
        # Check if RNDR client has been NOT RESPONDING recently
        if($global:RNDRNotRespondedSince -eq $null)
        { 
            foreach ($RNDRProcess in $RNDRProcesses) 
            {
                # Check if RNDR client is NOT RESPONDING.
                if(!$RNDRProcess.Responding)
                {
                    #Timestamp when client was not responding
                    $global:RNDRNotRespondedSince = Get-Date
                    Write-Host (Get-Date) : RNDR client is not responding. Waiting grace period.
                    
                    # Write to log file
                    Add-Logfile-Entry "RNDR client process not responding. Waiting grace period before stopping process."

                }
            }
        }
        else
        {
            # Delay kill command for some time as client might just be starting up
            if((New-TimeSpan -start $global:RNDRNotRespondedSince).TotalSeconds -gt $sleepRNDRNotResponding)
            {
                # Kill if still NOT RESPONDING
                foreach ($RNDRProcess in $RNDRProcesses) 
                {
                    # Check if RNDR client is NOT RESPONDING.
                    if(!$RNDRProcess.Responding)
                    {

                        Write-Host (Get-Date) : RNDR client is not responding. Stopping process now.
                    
                        # Write to log file
                        Add-Logfile-Entry "RNDR client process not responding. Grace period over, stopping process now."
                        
                        $global:RNDRRestarts = $global:RNDRRestarts + 1

                        Stop-Processes($RNDRProcessName)
                        break
                    }
                }

                # Set state to all processes responding
                $global:RNDRNotRespondedSince = $null

            }
        }
    }
}



# Helper fuction to check the Windows Registry key if the client is idle
Function Check-RNDR-Client-Idle {
    
    #Code to check if RNDR Client is currently idle. Returns $true or $false
    (Get-ItemProperty -Path Registry::HKEY_CURRENT_USER\SOFTWARE\OTOY -Name RNDR_IDLE -errorAction SilentlyContinue).RNDR_IDLE -eq 1

}


# Main function to launch the Dual workload
Function Launch-Dual-Workload {

    #For safety, only launch if really not running right now
    if (!(Check-Dual-Workload-Running))
    {
 
        # Run Nvidia-SMI to check for locked GPUs
        try{Start-Process -wait -WindowStyle Minimized "nvidia-smi" -ErrorAction SilentlyContinue}catch{}
        
        # Set overclocking profile to Dual
        If ($UseOverclocking)
        {
            if (Test-Path $OverclockingApp) 
            {
                Start-Process -WindowStyle Minimized $OverclockingApp $OverclockingCommandDual
                Add-Logfile-Entry "Overclocking set to $OverclockingCommandDual."
            }
            else
            {
                Add-Logfile-Entry "Cannot start overclocking because file does not exist. Please configure OverclockingApp in watchdog correctly. $OverclockingApp"
                Write-Host (Get-Date) : Cannot start overclocking because file does not exist. Please configure OverclockingApp in watchdog correctly. $OverclockingApp
            }
        }

 
 
        # ===== Add your code here ====
        #
        #
        #Add your code here how to start your dual workload
        #
        if (Test-Path $DualLauchCommand) 
        {
            if ($StartAsAdmin) 
            {
                $StartedProcess = Start-Process $DualLauchCommand -Verb RunAs -WindowStyle Minimized -PassThru -WorkingDirectory (Split-Path $DualLauchCommand -Parent)
            } 
            else
            {
                #Example code if your workload requires admin rights
                $StartedProcess = Start-Process $DualLauchCommand -WindowStyle Minimized -PassThru -WorkingDirectory (Split-Path $DualLauchCommand -Parent)
            }
        }
        else
        {
            Add-Logfile-Entry "Cannot start Dual because file does not exist. Please configure DualLauchCommand in watchdog correctly. $DualLauchCommand"
            Write-Host  -ForegroundColor Red (Get-Date) : Cannot start Dual because file does not exist. 
            Write-Host (Get-Date) : Please configure RNDRLauchCommand in watchdog correctly. $DualLauchCommand
        }
        #
        #
        # =====

        $global:DualStarts = $global:DualStarts + 1

        # Wait
        Start-Sleep -Seconds $sleepDualWarmup

        return $StartedProcess
        
    }
}


# Main function to shutdown the Dual Workload when RNDR gets a job
Function Stop-Dual-Workload {

    # ===== Add your code here ====
    #
    #
    # Add your code here how to stop your dual workload. 
    if($DualWebAPIShutdownCommand)
    {
        # If the user has configured a WebAPI command try to call it
        try{$response = (Invoke-RestMethod -Uri $DualWebAPIShutdownCommand)}catch{$_.Exception.Response.StatusCode.Value__}

        # Wait
        Start-Sleep -Seconds $sleepDualShutdown
    }    
    else
    {
        # If there is no WebAPI try a graceful shutdown
        if ($DualProcess.Responding)
        {
            $DualProcess.CloseMainWindow() | Out-Null

            # Wait
            Start-Sleep -Seconds $sleepDualShutdown        
        }
        
    }
    
    # And for the case this has not worked send a stop-process to kill any remaining Dual process (same as killing a process in taskmanager)
    Stop-Processes($DualProcessName)
    #
    #
    # =====


    # Set overclocking profile back to RNDR
    If ($UseOverclocking)
    {
        if (Test-Path $OverclockingApp) 
        {
            Start-Process -WindowStyle Minimized $OverclockingApp $OverclockingCommandRNDR
            Add-Logfile-Entry "Overclocking set to $OverclockingCommandRNDR."
        }
        else
        {
            Add-Logfile-Entry "Cannot start overclocking because file does not exist. Please configure OverclockingApp in watchdog correctly. $OverclockingApp"
            Write-Host (Get-Date) : Cannot start overclocking because file does not exist. Please configure OverclockingApp in watchdog correctly. $OverclockingApp
        }
    }

    # Wait
    Start-Sleep -Seconds $sleepDualShutdown
}


# Helper fuction to check the running processes for the Dual workload being active
Function Check-Dual-Workload-Running {

    # ===== Add your code here ====
    #
    #
    #Add your code here to check if the dual workload is currently running. The implementation does this via process name. Returns $true or $false.
    (Get-Process -Name $DualProcessName -ErrorAction SilentlyContinue) -ne $null
    #
    #
    # =====
}


# Helper function to write all-time values back to registry
Function Update-Registry-Runtimes {
        #Write new time write back to registry
        Set-ItemProperty -Path Registry::HKEY_CURRENT_USER\SOFTWARE\OTOY -Name Runtime_Watchdog -errorAction SilentlyContinue -Value $([math]::Round((New-TimeSpan -Start $StartDate).Totalhours + $alltimeWatchdog,2))
        Set-ItemProperty -Path Registry::HKEY_CURRENT_USER\SOFTWARE\OTOY -Name Runtime_RNDR -errorAction SilentlyContinue -Value $([math]::Round($RNDRRuntimeCounter + $alltimeRNDR,2))
        Set-ItemProperty -Path Registry::HKEY_CURRENT_USER\SOFTWARE\OTOY -Name Runtime_Dual -errorAction SilentlyContinue -Value $([math]::Round($DualRuntimeCounter + $alltimeDual,2))
        Set-ItemProperty -Path Registry::HKEY_CURRENT_USER\SOFTWARE\OTOY -Name Restarts_RNDR -errorAction SilentlyContinue -Value ($global:RNDRRestarts + $alltimeRNDRRestarts)
        Set-ItemProperty -Path Registry::HKEY_CURRENT_USER\SOFTWARE\OTOY -Name Starts_Dual -errorAction SilentlyContinue -Value ($global:DualStarts + $alltimeDualStarts)
}

# Helper function to update the UI with the current status and stats
Function Write-Watchdog-Status {
    
    $WatchdogFormatted = '{0:#,##0.00} hours' -f (New-TimeSpan -Start $StartDate).totalhours
    $RNDRFormatted = '{0:#,##0.00} hours' -f $RNDRRuntimeCounter
    $DualFormatted = '{0:#,##0.00} hours' -f $DualRuntimeCounter
    $alltimeWatchdogFormatted = '{0:#,##0} hours' -f $([math]::Floor((New-TimeSpan -Start $StartDate).Totalhours + $alltimeWatchdog))
    $alltimeRNDRFormatted = '{0:#,##0} hours' -f $([math]::Floor($RNDRRuntimeCounter + $alltimeRNDR))
    $alltimeDualFormatted = '{0:#,##0} hours' -f $([math]::Floor($DualRuntimeCounter + $alltimeDual))
    $alltimeRNDRRestartsFormatted = '{0:#,##0}' -f ($global:RNDRRestarts + $alltimeRNDRRestarts)
    $alltimeDualStartsFormatted = '{0:#,##0}' -f ($global:DualStarts + $alltimeDualStarts)
    
    Write-Progress -Id 1 -Activity "Current work: $CurrentActivity - $(Get-Date)" -Status "RNDR restarts $global:RNDRRestarts, alltime $alltimeRNDRRestartsFormatted - Dual starts $global:DualStarts, alltime $alltimeDualStartsFormatted"    
    Write-Progress -Id 2 -Activity "Watchdog uptime" -Status "$WatchdogFormatted, alltime $alltimeWatchdogFormatted" 
    Write-Progress -Id 3 -Activity "RNDR runtime" -Status "$RNDRFormatted, alltime $alltimeRNDRFormatted"
    Write-Progress -Id 4 -Activity "Dual runtime" -Status "$DualFormatted, alltime $alltimeDualFormatted"

    # Save stats to registry
    Update-Registry-Runtimes 
}

# Helper function to add a new entry to the log file
Function Add-Logfile-Entry {
    param(
        [parameter(Mandatory=$true)] $LogEntry
    )

    if ($LogEntry -eq "") 
    {
        Add-Content -Path $logFile -Value ""
    } 
    else 
    {
        Add-Content -Path $logFile -Value "$(Get-Date) - $logEntry" -Encoding UTF8
    }

}

# Helper function to shutdown processes by name
Function Stop-Processes {
    param(
        [parameter(Mandatory=$true)] $ProcessName
    )

    $ProcessList = Get-Process $ProcessName -ErrorAction SilentlyContinue

    # If processes exist
    if ($ProcessList) 
    {
        # Try graceful shutdown first
        $ProcessList.CloseMainWindow() | Out-Null

        # Wait
        Start-Sleep -Seconds $SleepKillProcess

        # Kill any processes which did not shut down cracefully
        Stop-Process $ProcessList -Force        
    }
}

# Function to download and replace the current version with the latest version from Github repository
Function Download-Latest-Watchdog {

    # Get tag and download URL of the latest version
    $tag = (Invoke-WebRequest "https://api.github.com/repos/$WatchdogGithubRepo/releases" | ConvertFrom-Json)[0].tag_name
    $url = "https://github.com/$WatchdogGithubRepo/archive/$tag.zip"
    $download_path = "$env:USERPROFILE\Downloads\$WatchdogGithubRepoName.zip"

    # Download the release
    Invoke-WebRequest -Uri $url -OutFile $download_path
    Get-Item $download_path | Unblock-File

    # Expand the zip archive and remove the version tag from the folder name
    Expand-Archive -Path $download_path -DestinationPath $currentPath -Force
    Remove-Item $currentPath\$WatchdogGithubRepoName -Force -Recurse -ErrorAction SilentlyContinue
    Move-Item $currentPath\$WatchdogGithubRepoName-* $currentPath\$WatchdogGithubRepoName -Force

    Add-Logfile-Entry "--- Latest Watchdog version $tag downloaded ---"

}

# If the user config file has errors the latest version is downloaded and the defect version gets replaced
Function Fix-Defect-Userconfig {

    Write-Host RNDR Watchdog Started at
    Write-Host (Get-Date)
    Write-Host

    # Delay startup for system to complete booting when using watchdog with autostart 
    Write-Host -ForegroundColor Red "Error: Userconfig RNDR_Watchdog_Userconfig.ini cannot be read or is invalid."
    Write-Host
    # ISSUE: for some reason the choice message does not show up in certain situations. Adding a redundant message as write-host.
    Write-Host Press D to replace with Default config and latest Watchdog version or Q to Quit application.
    choice /c QD /n /m "Press D to replace with Default config and latest Watchdog version or Q to Quit application."

    # If user pressed D start update of the application
    if ($LASTEXITCODE -eq 2)
    {
        Write-Host Updating Watchdog and replacing userconfig with default...

        # Get the latest version
        Download-Latest-Watchdog

        # Overwrite the script RNDR_Watchdog_DualUse.ps1 with the latest version
        Copy-Item $currentPath\$WatchdogGithubRepoName\RNDR_Watchdog_DualUse.ps1 $currentPath -Force

        # Try to backup the defect userconfig file
        Copy-Item $currentPath\RNDR_Watchdog_Userconfig.ini $currentPath\RNDR_Watchdog_Userconfig.bak -Force -ErrorAction SilentlyContinue
        
        # Overwrite the RNDR_Watchdog_Userconfig.ini with the lastest version
        Copy-Item $currentPath\$WatchdogGithubRepoName\RNDR_Watchdog_Userconfig.ini $currentPath\RNDR_Watchdog_Userconfig.ini -Force

        Add-Logfile-Entry "--- Replaced user config with default ---"
        Add-Logfile-Entry "Please edit the file RNDR_Watchdog_Userconfig.ini before launching the application again."
        Add-Logfile-Entry "A backup of your old config has been saved as RNDR_Watchdog_Userconfig.bak."

        Write-Host
        Write-Host The userconfig has been replaced.
        Write-Host
        Write-Host Please edit the file RNDR_Watchdog_Userconfig.ini before launching the application again.
        Write-Host A backup of your old config has been saved as RNDR_Watchdog_Userconfig.bak.
        Write-Host
        Write-Host Exiting the Watchdog.
        pause
    }
    exit
}

# Helper function to check if all keys being read do exist in the user config file. If a key is missing the config file is defect or not up to date.
Function Read-IniContent {

    param(
        [parameter(Mandatory=$true)] $Section,
        [parameter(Mandatory=$true)] $Name
    )


    if ($WatchdogConfig[$Section].ContainsKey($Name))
    {
        Return $WatchdogConfig[$Section][$Name]
    }
    else
    {
        # Download the latest user config file and replace the defect one
        Fix-Defect-Userconfig
    }

}


# Helper function to read .ini files with user variables
# Source: https://gallery.technet.microsoft.com/scriptcenter/ea40c1ef-c856-434b-b8fb-ebd7a76e8d91
Function Get-IniContent {  
      
    [CmdletBinding()]  
    Param(  
        [ValidateNotNullOrEmpty()]  
        [ValidateScript({(Test-Path $_) -and ((Get-Item $_).Extension -eq ".ini")})]  
        [Parameter(ValueFromPipeline=$True,Mandatory=$True)]  
        [string]$FilePath  
    )  
      
    Begin  
        {Write-Verbose "$($MyInvocation.MyCommand.Name):: Function started"}  
          
    Process  
    {  
        Write-Verbose "$($MyInvocation.MyCommand.Name):: Processing file: $Filepath"  
              
        $ini = @{}  
        switch -regex -file $FilePath  
        {  
            "^\[(.+)\]$" # Section  
            {  
                $section = $matches[1]  
                $ini[$section] = @{}  
                $CommentCount = 0  
            }  
            "^(;.*)$" # Comment  
            {  
                if (!($section))  
                {  
                    $section = "No-Section"  
                    $ini[$section] = @{}  
                }  
                $value = $matches[1]  
                $CommentCount = $CommentCount + 1  
                $name = "Comment" + $CommentCount  
                $ini[$section][$name] = $value  
            }   
            "(.+?)\s*=\s*(.*)" # Key  
            {  
                if (!($section))  
                {  
                    $section = "No-Section"  
                    $ini[$section] = @{}  
                }  
                $name,$value = $matches[1..2]  
                $ini[$section][$name] = $value  
            }  
        }  
        Write-Verbose "$($MyInvocation.MyCommand.Name):: Finished Processing file: $FilePath"  
        Return $ini  
    }  
          
    End  
        {Write-Verbose "$($MyInvocation.MyCommand.Name):: Function ended"}  
}









# ---- START OF THE WATCHDOG APPLICATION -----

$WatchdogGithubRepo = "rndr-man/rndr-watchdog"
$WatchdogGithubRepoName = "rndr-watchdog"


#Load user configuration stored in RNDR_Watchdog_DualUse_Userconfig.ini in same directory
try{$WatchdogConfig = Get-IniContent "$currentPath\RNDR_Watchdog_Userconfig.ini"}catch{Fix-Defect-Userconfig}

$StartsAsAdmin = if(($WatchdogConfig["watchdog"]["StartAsAdmin"]) -eq "true"){$true}else{$false}

# Elevate administrator rights and set same folder location.
if ($StartsAsAdmin -and !([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" " -Verb RunAs; exit }else{}

# Initialize other application variables
$RNDRClientLogs = "$env:localappdata\OtoyRndrNetwork\rndr_log.txt"
$CurrentActivity = "Startup"
$DualRuntime = 0
$RNDRRuntime = 0
$DualRuntimeCounter = 0
$RNDRRuntimeCounter = 0
$global:RNDRRestarts = 0
$global:DualStarts = 0
$alltimeRNDRRestarts = 0
$alltimeDualStarts = 0
$StartDate = Get-Date
$alltimeWatchdog = 0
$alltimeRNDR = 0
$alltimeDual = 0
$global:RNDRStartDate = $StartDate
$global:DualStartDate = $StartDate
$global:RNDRNotRespondedSince = $null
$DualProcess = $null
$tag = 0

# Initialize user variables from the .ini file

# [watchdog]
$UseOverclocking = if((Read-IniContent "watchdog" "UseOverclocking" ) -eq "true"){$true}else{$false}
$WindowWidth = Read-IniContent "watchdog" "WindowWidth" 
$WindowHeight = Read-IniContent "watchdog" "WindowHeight" 

#  rndr_app 
$RNDRClientLaunchCommand = Read-IniContent "rndr_app" "RNDRClientLaunchCommand" 
if (!(Test-Path $RNDRClientLaunchCommand)){$RNDRClientLaunchCommand = "$currentPath\$RNDRClientLaunchCommand"}
$RNDRProcessName = Read-IniContent "rndr_app" "RNDRProcessName" 

#  dual_app 
$DualLauchCommand = Read-IniContent "dual_app" "DualLauchCommand" 
if (!(Test-Path $DualLauchCommand)){$DualLauchCommand = "$currentPath\$DualLauchCommand"}
$DualProcessName = Read-IniContent "dual_app" "DualProcessName" 
$DualWebAPIShutdownCommand = Read-IniContent "dual_app" "DualWebAPIShutdownCommand" 

#  overclocking_app 
$OverclockingApp = Read-IniContent "overclocking_app" "OverclockingApp" 
if (!(Test-Path $OverclockingApp)){$OverclockingApp = "$currentPath\$OverclockingApp"}
$OverclockingCommandRNDR = Read-IniContent "overclocking_app" "OverclockingCommandRNDR" 
$OverclockingCommandDual = Read-IniContent "overclocking_app" "OverclockingCommandDual" 

#  logging 
$logFile = Read-IniContent "logging" "logFile" 
if (!(Test-Path $logFile)){$logFile = "$currentPath\$logFile"}

#  timer 
$WatchdogWarmup = Read-IniContent "timer" "WatchdogWarmup" 
$sleepIdle = Read-IniContent "timer" "sleepIdle" 
$sleepBusy = Read-IniContent "timer" "sleepBusy" 
$sleepIdleRetest = Read-IniContent "timer" "sleepIdleRetest" 
$sleepRNDRWarmup = Read-IniContent "timer" "sleepRNDRWarmup" 
$sleepRNDRNotResponding = Read-IniContent "timer" "sleepRNDRNotResponding" 
$SleepDualWarmup = Read-IniContent "timer" "SleepDualWarmup" 
$SleepDualShutdown = Read-IniContent "timer" "SleepDualShutdown" 
$SleepKillProcess = Read-IniContent "timer" "SleepKillProcess" 


# Read all-time values from windows registry
$alltimeWatchdog = (Get-ItemProperty -Path Registry::HKEY_CURRENT_USER\SOFTWARE\OTOY -Name Runtime_Watchdog -errorAction SilentlyContinue).Runtime_Watchdog
$alltimeRNDR = (Get-ItemProperty -Path Registry::HKEY_CURRENT_USER\SOFTWARE\OTOY -Name Runtime_RNDR -errorAction SilentlyContinue).Runtime_RNDR
$alltimeDual = (Get-ItemProperty -Path Registry::HKEY_CURRENT_USER\SOFTWARE\OTOY -Name Runtime_Dual -errorAction SilentlyContinue).Runtime_Dual
$alltimeRNDRRestarts = (Get-ItemProperty -Path Registry::HKEY_CURRENT_USER\SOFTWARE\OTOY -Name Restarts_RNDR -errorAction SilentlyContinue).Restarts_RNDR
$alltimeDualStarts = (Get-ItemProperty -Path Registry::HKEY_CURRENT_USER\SOFTWARE\OTOY -Name Starts_Dual -errorAction SilentlyContinue).Starts_Dual

[console]::Title = "RNDR Watchdog (Dual Use Version)"
[console]::WindowWidth= $WindowWidth
[console]::WindowHeight= $WindowHeight
[console]::BufferWidth=[console]::WindowWidth

Write-Host RNDR Watchdog $Release started at
Write-Host $StartDate
Write-Host

# Check tag of latest release in the Github repository
$tag = (Invoke-WebRequest "https://api.github.com/repos/$WatchdogGithubRepo/releases" | ConvertFrom-Json)[0].tag_name

# If this release has a different version then a new version is available
if ($tag -ne $Release)
{
    Write-Host -ForegroundColor Red A new version Watchdog $tag is available. Press U to update now.
    Write-Host
    Add-Logfile-Entry "A new version Watchdog $tag is available. Please consider updating."
}

# Delay startup for system to complete booting when using watchdog with autostart 
choice /c SU /n /t $WatchdogWarmup /d S /m "Waiting $WatchdogWarmup seconds. Press S to start now."

# If user pressed U start update of the application
if ($LASTEXITCODE -eq 2){
    Write-Host (Get-Date) : Updating Watchdog and restarting.
    Download-Latest-Watchdog

    # Overwrite the script RNDR_Watchdog_DualUse.ps1 with the new version
    Copy-Item $currentPath\$WatchdogGithubRepoName\RNDR_Watchdog_DualUse.ps1 $currentPath -Force

    Add-Logfile-Entry "---- Watchdog updated with release $tag ---- "

    #Restart the script to launch with the new version
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" "
    exit
}

Write-Host
Write-Host
Write-Host
Write-Host
Write-Host
Write-Host
Write-Host
Write-Host
Write-Host
Write-Watchdog-Status

# Write to log file
Add-Logfile-Entry ""
Add-Logfile-Entry ""
Add-Logfile-Entry "---- RNDR Watchdog $Release started ---- "

# At startup make sure RNDR client is running 
Launch-RNDR-Client



# ---- MAIN LOOP -----
# Run as long as watchdog is open
while ($true)
{
    #Loop as long as RNDR is IDLE
    while(Check-RNDR-Client-Idle)
    {
        
        $CurrentActivity = "Dual workload"
        Write-Watchdog-Status 

        # Check if Dual is not running
        if (!(Check-Dual-Workload-Running))
        { 

            # Before launching Dual, take another break and test before starting it to avoid that RNDR is not idle anymore.
            Start-Sleep -Seconds $sleepIdleRetest
            
            if (Check-RNDR-Client-Idle)
            {
                
                # If RNDR was running before then calculate runtime
                if($global:RNDRStartDate)
                {
                    $LastRun = (New-TimeSpan -Start $global:RNDRStartDate).Totalhours
                    $RNDRRuntime = $RNDRRuntime + $LastRun
                    $global:RNDRStartDate = $null
                
                    # Write event to log
                    Add-Logfile-Entry ""
                    Add-Logfile-Entry "RNDR runtime - $([math]::Round($LastRun,2)) hours."
                    Add-Logfile-Entry "RNDR total runtime - $([math]::Round($RNDRRuntime,2)) hours."
                    Add-Logfile-Entry ""
                    Add-Logfile-Entry "Dual started. RNDR idle."
                
                }
                
                # Update timestamp when Dual started
                $global:DualStartDate = Get-Date
                Write-Host (Get-Date) : Dual started. RNDR idle.

                # Start Dual if not running
                $DualProcess = Launch-Dual-Workload

            }
            else
            {
                Write-Host (Get-Date): Dual start PREVENTED. RNDR not idle. 
                # Write event to log
                Add-Logfile-Entry " Dual start PREVENTED. RNDR not idle."
            }
        }   

        # Make sure RNDR client is still running 
        Keep-RNDR-Client-Running
        
        # Wait 
        Start-Sleep -Seconds $sleepIdle

        
        if($global:DualStartDate){$DualRuntimeCounter = $DualRuntime + (New-TimeSpan -Start $global:DualStartDate).Totalhours}
        

    }

    # --- Loop exited as RNDR is no longer IDLE ----
    
    $CurrentActivity = "Rendering"
    Write-Watchdog-Status
    
    # Check if Dual is  running
    if (Check-Dual-Workload-Running)
    {
        # Shutdown Dual
        Write-Host (Get-Date) : Dual shutdown signal sent. RNDR active.
        Stop-Dual-Workload

        # If Dual was running before then calculate runtime
        if($global:DualStartDate)
        {
            # Add last run duration to the runtime
            $LastRun = (New-TimeSpan -Start $global:DualStartDate).Totalhours
            $DualRuntime = $DualRuntime + $LastRun
            $global:DualStartDate = $null
        }


        # Write event to log
        Add-Logfile-Entry "Dual shutdown signal sent. RNDR active."
        Add-Logfile-Entry ""
        Add-Logfile-Entry "Dual runtime - $([math]::Round($LastRun,2)) hours."
        Add-Logfile-Entry "Dual total runtime - $([math]::Round($DualRuntime,2)) hours."

        # Update timestamp when RNDR started
        $global:RNDRStartDate = Get-Date
    }

    # Make sure RNDR client is still running 
    Keep-RNDR-Client-Running

    # Wait
    Start-Sleep -Seconds $sleepBusy

    if($global:RNDRStartDate){$RNDRRuntimeCounter = $RNDRRuntime + (New-TimeSpan -Start $global:RNDRStartDate).Totalhours}
    
}