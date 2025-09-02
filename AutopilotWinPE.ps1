##This script will check if the device is in Autopilot. If it is, it will print the group tag of the device.
## It will then proceed to remove the Intune record if required, then install Windows & drivers


function MgGraph-Authentication {
 
    ## Credetnails required to auth ##
    try {
        Write-Host "Connecting to MS Graph..." -ForegroundColor Cyan
       
        Write-Host "#######################################################################" -ForegroundColor Green
        Write-Host "## FOLLOW THE INSTRUCTIONS BELOW TO AUTHENTICATE TO BUILD THE DEVICE ##" -ForegroundColor Green
        Write-Host "#######################################################################`n" -ForegroundColor Green
        
        Set-ExecutionPolicy RemoteSigned -Force
        Install-Module PowershellGet -Force -SkipPublisherCheck
        Install-Module Microsoft.Graph -Force -SkipPublisherCheck
        Connect-MgGraph -UseDeviceCode -NoWelcome
        Write-Host "Connected successfuly" -ForegroundColor Green
        downloadPreReqs
 
    } catch {
        Write-Host "Error connecting to graph: $_." -ForegroundColor Red
        Read-Host -Prompt "Press Enter to exit"
    }
}
 
function downloadPreReqs {
 
    Write-Host "Creating path for pre-reqs" -ForegroundColor Cyan
    New-Item -ItemType Directory -Path "X:\Autopilot"
 
    Write-Host "Downloading Pre-reqs..." -ForegroundColor Cyan
    Invoke-WebRequest https://raw.githubusercontent.com/harris-bowman/IntuneTesting/refs/heads/main/Create_4kHash_using_OA3_Tool.ps1 -OutFile X:\Autopilot\Create_4kHash_using_OA3_Tool.ps1
    Invoke-WebRequest https://raw.githubusercontent.com/harris-bowman/IntuneTesting/refs/heads/main/OA3.cfg -OutFile X:\Autopilot\OA3.cfg
    Invoke-WebRequest https://raw.githubusercontent.com/harris-bowman/IntuneTesting/refs/heads/main/PCPKsp.dll -OutFile X:\Autopilot\PCPKsp.dll
    Invoke-WebRequest https://raw.githubusercontent.com/harris-bowman/IntuneTesting/refs/heads/main/input.xml -OutFile X:\Autopilot\input.xml
    Invoke-WebRequest https://raw.githubusercontent.com/harris-bowman/IntuneTesting/refs/heads/main/oa3tool.exe -OutFile X:\Autopilot\oa3tool.exe
    Write-Host "Pre-reqs downloaded!" -ForegroundColor Green
 
    AutopilotDeviceEnrolmentCheck
}
 
function AutopilotDeviceEnrolmentCheck {
    ## Check if the device is already in Autopilot.
    Write-Host "Checking if device is already enrolled in Autopilot" -ForegroundColor Cyan
    $serialNumber = (Get-WmiObject -Class Win32_BIOS).SerialNumber
    $global:autopilotRecord = Get-MgDeviceManagementWindowsAutopilotDeviceIdentity | Where-Object serialNumber -eq "$serialNumber" | Select-Object serialNumber, GroupTag, Model, LastContactedDateTime
 
 
    if ($autopilotRecord) {
        $enrolledGroupTag = Get-MgDeviceManagementWindowsAutopilotDeviceIdentity | Where-Object serialNumber -eq "$serialNumber" | Select-Object -ExpandProperty GroupTag
        Write-Host "Device already enrolled with Group Tag: $enrolledGroupTag" -ForegroundColor Green
        IntuneDeviceCheck
        }
    else {
        Write-Host "Device is not enrolled. Moving to enrolment step" -ForegroundColor Yellow
        IntuneDeviceCheck
        }
 
}
 
 
function IntuneDeviceCheck {
    ## Check if the device is already in Intune
 
    Write-Host "Checking if device is in Intune..." -ForegroundColor Cyan
    $serialNumber = (Get-WmiObject -Class Win32_BIOS).SerialNumber
    $intuneRecord = Get-MgDeviceManagementManagedDevice | Where-Object serialNumber -eq "$serialNumber" | Select-Object serialNumber, deviceName, enrolledDateTime, lastSyncDateTime
   
    if ($intuneRecord) {
        $deviceName = Get-MgDeviceManagementManagedDevice | Where-Object serialNumber -eq "$serialNumber" | Select-Object -ExpandProperty deviceName
        Write-Host "Device is in Intune: $deviceName." -ForegroundColor Yellow
        Write-Host "This will be automatically removed in 5 seconds to prevent conflict during Autopilot." -ForegroundColor Yellow
        Start-Sleep 5
        removeIntuneRecord
        }
    else {
        Write-Host "Device is not in Intune. Moving to next step." -ForegroundColor Green
        if ($autopilotRecord) {
            Start-OSD
            }
        else {
            Start-AutopilotEnrolment
            }
        }
}
 
function removeIntuneRecord {
    ## Removes Intune record if it exists
    $serialNumber = (Get-WmiObject -Class Win32_BIOS).SerialNumber
    $intuneRecord = Get-MgDeviceManagementManagedDevice | Where-Object serialNumber -eq "$serialNumber" | Select-Object serialNumber, deviceName, enrolledDateTime, lastSyncDateTime, Id
    $deviceName = Get-MgDeviceManagementManagedDevice | Where-Object serialNumber -eq "$serialNumber" | Select-Object -ExpandProperty deviceName
    $managedDeviceId = Get-MgDeviceManagementManagedDevice | Where-Object serialNumber -eq "$serialNumber" | Select-Object -ExpandProperty Id
 
 
    Write-Host "Removing intune record: $deviceName..." -ForegroundColor Cyan
    try {
        Remove-MgDeviceManagementManagedDevice -ManagedDeviceId $managedDeviceId
        Write-Host "Device removed successfuly!" -ForegroundColor Green
    } catch {
        Write-Host "Failed to remove device: $_" -ForegroundColor Red
        Write-Host "$deviceName has not been removed. You will need to remove the device manually before Autopilot!" -ForegroundColor Red
    }
    if ($autopilotRecord) {
        Start-OSD
        }
    else {
        Start-AutopilotEnrolment
        }
}
 
function Start-AutopilotEnrolment {
    ## Grab required details and create Autopilot CSV
    $SerialNumber = (Get-WmiObject -Class Win32_BIOS).SerialNumber
 
    Write-Host "Welcome to Autopilot Enrolment" -ForegroundColor Cyan
   
    $GroupTag = "SmarT User"
   
    $OutputFile = "X:\Autopilot\$SerialNumber.CSV"
   
    X:\Autopilot\Create_4kHash_using_OA3_Tool.ps1 -GroupTag $GroupTag -OutputFile $OutputFile
    Write-Host "Creation of Autopilot CSV file succeeded!" -ForegroundColor Green
    Write-Host "Starting Upload to Intune now via MS Graph." -ForegroundColor Cyan
    Start-Sleep -Seconds 10
    Start-AutopilotGraphUpload
    Start-Sleep -Seconds 10
    }
 
    function Start-AutopilotGraphUpload {
 
    ## Import AutoPilot CSV via Microsoft Graph
 
    function Get-AutoPilotData {
        param (
            [string]$CsvPath
        )
        try {
            $csvData = Import-Csv -Path $CsvPath -Encoding UTF8
            $deviceList = @()
 
            foreach ($row in $csvData) {
                $hardwareIdentifierBase64 = if ([string]::IsNullOrWhiteSpace($row."Hardware Hash")) {
                    "" # Leave empty if no hardware hash
                } else {
                    $bytes = [System.Convert]::FromBase64String($row."Hardware Hash")
                    [System.Convert]::ToBase64String($bytes)
                }
 
                $deviceObj = @{
                    "@odata.type" = "#microsoft.graph.importedWindowsAutopilotDeviceIdentity"
                    groupTag = $row."Group Tag"
                    serialNumber = $row."Device Serial Number"
                    productKey = if ($row."Windows Product ID") { $row."Windows Product ID" } else { $null }
                    hardwareIdentifier = $hardwareIdentifierBase64
                }
                $deviceList += $deviceObj
            }
 
            return $deviceList | ConvertTo-Json -Depth 10
        } catch {
            Write-Host "Error reading CSV file: $_" -ForegroundColor Red
            Read-Host -Prompt "Press Enter to exit"
            exit
        }
    }
 
 
 
 
    # Function to upload data to Intune via Microsoft Graph
    function Upload-AutoPilotData {
        param (
            [string]$JsonData
        )
 
        $uri = "https://graph.microsoft.com/v1.0/deviceManagement/importedWindowsAutopilotDeviceIdentities"
 
        try {
            $response = Invoke-MgGraphRequest -Method POST -Uri $uri -Body $JsonData -ContentType "application/json"
            return $response
        } catch {
            Write-Host "Error uploading data to Intune: $($_.Exception.Response.StatusCode.Value__) $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "Graph API Response: $($_.Exception.Response.Content.ReadAsStringAsync().Result)" -ForegroundColor Red
            Read-Host -Prompt "Press Enter to exit"
            exit
        }
    }
 
 
    function Main {
        $SerialNumber = (Get-WmiObject -Class Win32_BIOS).SerialNumber
 
        # Modify the path to AutoPilot CSV file
        $csvPath = "X:\Autopilot\$SerialNumber.CSV"
   
        # Get and format AutoPilot data
        $jsonData = Get-AutoPilotData -CsvPath $csvPath
 
        # Print JSON Payload for debugging (Remove in production)
        Write-Host "JSON Payload: $jsonData" -ForegroundColor Magenta
 
        # Upload data to Intune
        $response = Upload-AutoPilotData -JsonData $jsonData
 
        # Check response
        if ($response -ne $null) {
            Write-Host "AutoPilot data uploaded successfully." -ForegroundColor Green
        } else {
            Write-Host "Failed to upload AutoPilot data." -ForegroundColor Red
            Read-Host -Prompt "Press Enter to exit"
        }
    }
 
    Main
    Start-OSD
}
 
function Start-TPMAttestationFix {
    ## Creates registry key to fix TPM attestation error that can sometimes appear during Autopilot
    Write-Host "Adding registry key for TPM attestation fix" -ForegroundColor Cyan
    reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\OOBE /v SetupDisplayedEula /t REG_DWORD /d 00000001 /f
    Write-Host "Reg key added!" -ForegroundColor Green
}
 
function Start-OSD {
 
    ##ZTI so no prompts, skip adding Autopilot profile JSON
    
    Start-OSDCloud -FindImageFile -ZTI -SkipAutopilot 
    Write-Host "Build complete!" -ForegroundColor Green
 
    Start-TPMAttestationFix
 
    Write-Host "Shutting down in 3 seconds!" -ForegroundColor Cyan
    Start-Sleep -Seconds 3
    wpeutil shutdown
}
 
$SkipAnswerInput = Read-Host("Enter the word 'skip' to skip uploading the device's hash to Windows Autopilot and to instantly start rebuilding the device. Otherwise, press enter.")
if ($SkipAnswerInput -eq "skip") {
    Write-Host "OSDCloud build automation - Windows reinstall only." -ForegroundColor Cyan
    Start-OSD
} else {
    Write-Host "OSDCloud build automation with Autopilot enrolment" -ForegroundColor Cyan
    MgGraph-Authentication
}