<#
    .SYNOPSIS
        This function converts a UPD Profile to an FSLogix Profile Container.
    
    .DESCRIPTION
        The Convert-UPDProfile Command is used to migrate a UPD Profile to an FSLogix Profile Container.
        The expected input is a Source Path, Parent Path, or CSV containing Source Paths with a Header of "Path".
        The source UPD Profile is mounted. A VHD/x of the specified size is created at the destination, mounted, and the folder structure from each path inputted is mirrored to its respective destination VHD in a Profile folder. (As expected by FSLogix.)
        Robocopy is used to copy the File/Folder structure.
        New-VHD (Hyper-V module) is used to create the destination VHD.
    
    .PARAMETER ParentPath
        ParentPath is expected to be in UNC format, with all child items being UPD VHD or VHDX files. A simple example of this would be "C:\Users" where each child item is a VHD/X.
    
    .PARAMETER ProfilePath
        ProfilePath is a single profile. And example of this would be "C:\Users\UserDisk1.vhdx"
    
    .PARAMETER CSV
        A CSV list can be used if profiles form various network locations are being migrated. The CSV should contain individual profiles VHDs under a Header of "Path" and are in UNC format. Example "C:\Users\UserDisk1.vhd"

    .PARAMETER Target
        A UNC path to the FSLogix Profile Share. This is expected to be a UNC path. Example: "\\SERVER\FSLogixProfiles$"

    .PARAMETER VHDMaxSizeGB
        Specify the Max VHD Size of all VHDs in a given batch. The parameter expects Integers resembling Gigabytes (GB). Example: -VHDMaxSizeGB 15
        The VHDs are created as dynamic disk, so only used space from the profile with expand the actual VHD Size on-disk.

    .PARAMETER VHDLogicalSectorSize
        Specify Logical Sector Size of VHD/VHDX. Options are 4k (4096 Bytes) or 512 (512 Bytes).

    .PARAMETER VHD
        By Default the command will create a VHDX file at the destination unless this flag is set. If the -VHD flag is set, a VHD will be created at the destination for each profile.

    .PARAMETER SwapDirectoryNameComponents
        By default, directory name is SID_Username. If SwapDirectoryNameComponents is set, directory name will be Username_SID.
        Set this if the GPO Setting 'Swap directory name components' is enabled.

    .PARAMETER IncludeRobocopyDetail
        Robocopy details are supressed by default and will just show an overall progress bar of moved bytes. If a terminal output of transmitted files in real-time is desired, uses this flag.

    .PARAMETER LogPath
        Specifies log path. The file format is Text based, so a .log or .txt is expected.

    .EXAMPLE
        Convert-UPDProfile -ParentPath "C:\Users\" -Target "\\Server\FSLogixProfiles$" -VHDMaxSizeGB 20 -VHDLogicalSectorSize 512

        The example above will take inventory of all child-item directories, create a VHDX with a max size of 20GB, and copy the source profiles to their respective destinations.
        
    .EXAMPLE
        Convert-UPDProfile -ParentPath F:\Shares\UPDs -Target F:\Shares\FSLogixProfiles -VHDMaxSizeGB 30 -VHDLogicalSectorSize 4K -SwapDirectoryNameComponents -LogPath F:\LogFiles\UPDtoFSLogixMigration\Log.txt

        The example above will take inventory of all child-item directories, create a VHDX with a max size of 30GB, and copy the source profiles to their respective destinations.
        
        FSLogix Profile directory names will be created using username_SID to work with GPO setting 'Swap directory name components'
    
        .EXAMPLE
        Convert-UPDProfile -ProfilePath "C:\Users\UserDisk1.vhd" -Target "\\Server\FSLogixProfiles$" -VHDMaxSizeGB 20 -VHDLogicalSectorSize 512 -VHD -IncludeRobocopyDetail -LogPath C:\temp\Log.txt

        The example above will take the User1 profile, create a VHD with a max size of 20GB, and copy the source profiles to their respective destinations. /TEE will be added to Robocopy parameters, and a Log will be generated at C:\Temp\Log.txt

    .NOTES
        Author: Dom Ruggeri
        Last Edit: 7/23/19

        Modified by Mike Driest 10/14/2022.  Added Parameter SwapDirectoryNameComponents
    
    #>
Function Convert-UPDProfile {
    
    [CmdletBinding(SupportsShouldProcess = $True, DefaultParameterSetName = 'ParentPath')]
    Param (
        [Parameter(Mandatory = $True, ParameterSetName = 'ParentPath')]
        [string]$ParentPath,
                
        [Parameter(Mandatory = $True, ParameterSetName = 'ProfilePath')]
        [string]$ProfilePath,
    
        [Parameter(Mandatory = $True, ParameterSetName = 'CSV')]
        [string]$CSV,
    
        [Parameter(Mandatory = $True)]
        [string]$Target,

        [Parameter(Mandatory = $True)]
        [uint64]$VHDMaxSizeGB,

        [Parameter(Mandatory = $True)]
        [validateSet('4K', '512')]
        [string]$VHDLogicalSectorSize,

        [Parameter()]
        [switch]$VHD,

        [Parameter()]
        [switch]$SwapDirectoryNameComponents,

        [Parameter()]
        [switch]$IncludeRobocopyDetail,

        [Parameter()]
        [string]$LogPath
    )
        
    Begin {
        $SuccessProfileList = @()
        $FailedProfileList = @()
        $SkippedProfileList = @()
        $CopyParams = @{ }
        $Success = 0
        $Skipped = 0
    }
        
    Process {
        if ($VHD) {
            $Params = @{
                'VHD' = $true
                'SwapDirectoryNameComponents' = $SwapDirectoryNameComponents
            }
        }
        else {
            $Params = @{
                'SwapDirectoryNameComponents' = $SwapDirectoryNameComponents
            }
        }
        
        if ($ParentPath) {
            if ($pscmdlet.ShouldProcess($ParentPath, 'Creating Batch Object')) {
                try {
                    $BatchObject = Get-ProfileSource -ParentPath $ParentPath | New-MigrationObject -Target $Target @Params -ErrorAction Stop
                }
                catch {
                    Write-Log -Message "Cannot create batch object" -LogPath $LogPath
                    Write-Log -Message $_ -LogPath $LogPath
                }
                $SourcePath = $ParentPath
            }
        }
        
        if ($ProfilePath) {
            if ($pscmdlet.ShouldProcess($ProfilePath, 'Creating Batch Object')) {
                try {
                    $BatchObject = Get-ProfileSource -ProfilePath $ProfilePath | New-MigrationObject -Target $Target @Params -ErrorAction Stop
                }
                catch {
                    Write-Log -Message "Cannot create batch object" -LogPath $LogPath
                    Write-Log -Message $_ -LogPath $LogPath
                }
                $SourcePath = $ProfilePath
            }
        }
        
        if ($CSV) {
            if ($pscmdlet.ShouldProcess($CSV, 'Creating Batch Object')) {
                try {
                    $BatchObject = Get-ProfileSource -CSV $CSV | New-MigrationObject -Target $Target @Params -ErrorAction Stop
                }
                catch {
                    Write-Log -Message "Cannot create batch object" -LogPath $LogPath
                    Write-Log -Message $_ -LogPath $LogPath
                }
                $SourcePath = $CSV
            }
        }
    
        $BatchStartTime = get-date
        foreach ($P in $BatchObject) {
            Write-Output "-----------------------------------------------------------------------------" 4>&1 | Write-Log -LogPath $LogPath
            Write-Output "Beginning Migration of $(($P).ProfilePath)" 4>&1 | Write-Log -LogPath $LogPath
            Write-Output "-----------------------------------------------------------------------------" 4>&1 | Write-Log -LogPath $LogPath
            If (($P).Target -ne "Cannot Copy") {
                $ProfileStartTime = Get-Date
                if (!(Test-Path (($P).Target.Substring(0, ($P).Target.LastIndexOf('.')) + "*"))) {
                    try {
                        $UPDProfilePath = (Mount-UPDProfile -ProfilePath (($P).ProfilePath) -ErrorAction Stop).drive
                    }
                    catch {
                        Write-Log -Message "Cannot mount source drive" -LogPath $LogPath
                        Write-Log -Message $_ -LogPath $LogPath
                    }

                    try {
                        $Drive = (New-ProfileDisk -ProfilePath $UPDProfilePath -Target (($P).Target) -Username (($P).Username) -Size $VHDMaxSizeGB -SectorSize $VHDLogicalSectorSize -ErrorAction Stop).Drive
                    }
                    catch {
                        Write-Log -Message "Cannot creat new drive" -LogPath $LogPath
                        Write-Log -Message $_ -LogPath $LogPath
                    }
                    if ($Drive) {
                        if ($IncludeRobocopyDetail) {
                            $CopyParams = @{
                                "IncludeRobocopyDetail" = $True
                            }
                        }
                        try {
                            Copy-Profile -ProfilePath $UPDProfilePath -Drive $Drive @CopyParams -ErrorAction Stop
                        }
                        catch {
                            Write-Log -Message "Could not copy" -LogPath $LogPath
                            Write-Log -Message $_ -LogPath $LogPath
                        }

                        $Destination = "$Drive`Profile"

                        Write-Output "Verifying Source Matches Destination" 4>&1 | Write-Log -LogPath $LogPath
                        if ($null -eq (Compare-Object -ReferenceObject (Get-ChildItem $UPDProfilePath -Recurse -force) -DifferenceObject (Get-ChildItem $Destination -Recurse -force))) {
                            Write-Output "Source and Destination match." 4>&1 | Write-Log -LogPath $LogPath
                            Write-Output "Source and Destination match."
                        }
                        Else { 
                            write-warning "Source and Destination do not match." 3>&1 | Write-Log -LogPath $LogPath
                            write-warning "Source and Destination do not match."
                        }

                        try {
                            New-ProfileReg -UserSID ($P).UserSID -Drive $Drive -ErrorAction Stop
                            Write-Output "Adding User and System NTFS Permissions" 4>&1 | Write-Log -LogPath $LogPath
                        }
                        catch {
                            Write-Log -Message "Could not copy" -LogPath $LogPath
                            Write-Log -Message $_ -LogPath $LogPath
                        }

                        try {
                            icacls $Destination /setowner SYSTEM
                            icacls $Destination /inheritance:r
                            icacls $Destination /grant $env:userdomain\$(($P).Username)`:`(OI`)`(CI`)F
                            icacls $Destination /grant SYSTEM`:`(OI`)`(CI`)F
                            icacls $Destination /grant Administrators`:`(OI`)`(CI`)F
                            icacls $Destination /grant $env:userdomain\$(($P).Username)`:`(OI`)`(CI`)F
    
                            icacls (($P).Target | Split-Path) /setowner $env:userdomain\$(($P).Username) /T /C
                            icacls (($P).Target | Split-Path) /grant $env:userdomain\$(($P).Username)`:`(OI`)`(CI`)F /T

                            attrib -H -S $Destination /S /D
                        }
                        catch {
                            Write-Log -Message "Could not Add Permissions to Disk" -LogPath $LogPath
                            Write-Log -Message $_ -LogPath $LogPath
                        }

                        Write-Output "Dismounting $(($P).Target)" 4>&1 | Write-Log -LogPath $LogPath

                        try {
                            Dismount-VHD (($P).Target) -ErrorAction Stop
                        }
                        catch {
                            Write-Log -Message "Cannot dismount Target drive" -LogPath $LogPath
                            Write-Log -Message $_ -LogPath $LogPath
                        }

                        Write-Output "Dismounting $(($P).ProfilePath)"
                        
                        try {
                            Dismount-VHD (($P).ProfilePath) -ErrorAction Stop
                        }
                        catch {
                            Write-Log -Message "Cannot dismount Srouce drive" -LogPath $LogPath
                            Write-Log -Message $_ -LogPath $LogPath
                        }

                        $ProfileEndTime = Get-Date
                        $ProfileDuration = "{0:hh\:mm\:ss}" -f ([TimeSpan] (New-TimeSpan -Start $ProfileStartTime -End $ProfileEndTime))
                        Write-Output "$(($P).ProfilePath) Migrated. Duration: $ProfileDuration" | Write-Log -LogPath $LogPath
                        Write-Output "$(($P).ProfilePath) Migrated. Duration: $ProfileDuration"
                        if (Test-path ($P).Target) {
                            $Success++
                            $SuccessProfileList += ($P).ProfilePath
                        }
                    }
                    else { 
                        Write-Error "Could not create or mount target drive." 2>&1 | Write-Log -LogPath $LogPath
                        Write-Error "Could not create or mount target drive."
                    }
                }
                Else {
                    Write-Warning "Profile $(($P).Target.Substring(0, ($P).Target.LastIndexOf('.'))) already exists. Skipping." 3>&1 | Write-Log -LogPath $LogPath
                    Write-Warning "Profile $(($P).Target.Substring(0, ($P).Target.LastIndexOf('.'))) already exists. Skipping."
                    $Skipped++
                    $SkippedProfileList += ($P).ProfilePath   
                }
            }
            elseif (($P).Target -eq "Cannot Copy") {
                Write-Warning "Profile $(($P).ProfilePath) Could not resolve to AD User. Cannot copy." 3>&1 | Write-Log -LogPath $LogPath
                Write-Warning "Profile $(($P).ProfilePath) Could not resolve to AD User. Cannot copy."
                $FailedProfileList += ($P).ProfilePath
            }
        }
    }
        
    End {
        $BatchEndTime = get-date
        $BatchDuration = "{0:hh\:mm\:ss}" -f ([TimeSpan] (New-TimeSpan -Start $BatchStartTime -End $BatchEndTime))
        Write-Output "
-----------------------------------------------------
Profile Migration Completed. 


Source: $SourcePath
Target: $Target

Start time: $BatchStartTime
End time: $BatchEndTime
Duration: $BatchDuration
    
Total Profiles: $(($batchObject | Measure-Object).count)
Eligible Profiles: $(($batchObject | Where-Object Target -NE "Cannot Copy" | Measure-Object).count)
Successful Migrations: $success
Skipped Migrations: $skipped
Failed Migrations: $($(($batchobject | Measure-Object).count) - $($Success) - $($Skipped))"

        if (($SuccessProfileList | Measure-Object).count -gt 0) {
            Write-Output "
Successful Migration List:"
            $SuccessProfileList
        }

        if (($SkippedProfileList | Measure-Object).count -gt 0) {
            Write-Output "
Skipped Migration List:"
            $SkippedProfileList
        }

        if (($FailedProfileList | Measure-Object).count -gt 0) {
            Write-Output "
Failed Migration List:"
            $FailedProfileList
        }
        Write-Output "
-----------------------------------------------------
"
        If ($LogPath) {
            Add-Content -Path $LogPath -Value "`n"
            Add-Content -Path $LogPath -Value "***************************************************************************************************"
            Add-Content -Path $LogPath -Value "$([DateTime]::Now) - Finished processing"
            Add-Content -Path $LogPath -Value "***************************************************************************************************"
        }
    }
}