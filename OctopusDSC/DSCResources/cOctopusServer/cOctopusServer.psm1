$installStateFile = "$($env:SystemDrive)\Octopus\Octopus.Server.DSC.installstate"

function Get-TargetResource
{
  [OutputType([Hashtable])]
  param (
    [ValidateSet("Present", "Absent")]
    [string]$Ensure = "Present",
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Name,
    [ValidateSet("Started", "Stopped")]
    [string]$State = "Started",
    [ValidateNotNullOrEmpty()]
    [string]$DownloadUrl = "https://octopus.com/downloads/latest/WindowsX64/OctopusServer",
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$WebListenPrefix,
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$SqlDbConnectionString,
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$OctopusAdminUsername,
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$OctopusAdminPassword,
    [bool]$UpgradeCheck = $true,
    [bool]$UpgradeCheckWithStatistics = $true,
    [string]$WebAuthenticationMode = 'UsernamePassword',
    [bool]$ForceSSL = $false,
    [int]$ListenPort = 10943
  )

  Write-Verbose "Checking if Octopus Server is installed"
  $installLocation = (Get-ItemProperty -path "HKLM:\Software\Octopus\Octopus" -ErrorAction SilentlyContinue).InstallLocation
  $present = ($null -ne $installLocation)
  Write-Verbose "Octopus Server present: $present"

  $existingEnsure = if ($present) { "Present" } else { "Absent" }

  $serviceName = (Get-ServiceName $Name)
  Write-Verbose "Checking for Windows Service: $serviceName"
  $serviceInstance = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
  $existingState = "Stopped"
  if ($null -ne $serviceInstance)
  {
    Write-Verbose "Windows service: $($serviceInstance.Status)"
    if ($serviceInstance.Status -eq "Running")
    {
      $existingState = "Started"
    }

    if ($existingEnsure -eq "Absent")
    {
      Write-Verbose "Since the Windows Service is still installed, the service is present"
      $existingEnsure = "Present"
    }
  }
  else
  {
    Write-Verbose "Windows service: Not installed"
    $existingEnsure = "Absent"
  }

  $existingDownloadUrl = $null
  $existingWebListenPrefix = $null
  $existingSqlDbConnectionString = $null
  $existingForceSSL = $null
  $existingOctopusUpgradesAllowChecking = $null
  $existingOctopusUpgradesIncludeStatistics = $null
  $existingListenPort = $null
  $existingOctopusAdminUsername = $null
  $existingOctopusAdminPassword = $null

  if ($existingEnsure -eq "Present") {
    $existingConfig = Import-ServerConfig "$($env:SystemDrive)\Octopus\OctopusServer.config" "$($env:ProgramFiles)\Octopus Deploy\Octopus\Octopus.Server.exe"
    $existingSqlDbConnectionString = $existingConfig.OctopusStorageExternalDatabaseConnectionString
    $existingWebListenPrefix = $existingConfig.OctopusWebPortalListenPrefixes
    $existingForceSSL = $existingConfig.OctopusWebPortalForceSsl
    $existingOctopusUpgradesAllowChecking = $existingConfig.OctopusUpgradesAllowChecking
    $existingOctopusUpgradesIncludeStatistics = $existingConfig.OctopusUpgradesIncludeStatistics
    $existingListenPort = $existingConfig.OctopusCommunicationsServicesPort
    if (Test-Path $installStateFile) {
      $installState = (Get-Content -Raw -Path $installStateFile | ConvertFrom-Json)
      $existingDownloadUrl = $installState.DownloadUrl
      $existingOctopusAdminUsername = $installState.OctopusAdminUsername
      $existingOctopusAdminPassword = $installState.OctopusAdminPassword
    }
  }

  $currentResource = @{
    Name = $Name;
    Ensure = $existingEnsure;
    State = $existingState;
    DownloadUrl = $existingDownloadUrl;
    WebListenPrefix = $existingWebListenPrefix;
    SqlDbConnectionString = $existingSqlDbConnectionString;
    ForceSSL = $existingForceSSL
    UpgradeCheck = $existingOctopusUpgradesAllowChecking
    UpgradeCheckWithStatistics = $existingOctopusUpgradesIncludeStatistics
    ListenPort = $existingListenPort
    OctopusAdminUsername = $existingOctopusAdminUsername
    OctopusAdminPassword = $existingOctopusAdminPassword
  }

  return $currentResource
}

function Import-ServerConfig
{
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [string] $Path,
    [Parameter(Mandatory)]
    [string] $OctopusServerExePath
  )

  Write-Verbose "Importing server configuration file from '$Path'"

  if (-not (Test-Path -LiteralPath $Path))
  {
    throw "Config path '$Path' does not exist."
  }

  $file = Get-Item -LiteralPath $Path -ErrorAction Stop
  if ($file -isnot [System.IO.FileInfo])
  {
    throw "Config path '$Path' does not refer to a file."
  }

  if (-not (Test-Path -LiteralPath $OctopusServerExePath))
  {
    throw "Octopus.Server.exe path '$OctopusServerExePath' does not exist."
  }

  $exeFile = Get-Item -LiteralPath $OctopusServerExePath -ErrorAction Stop
  if ($exeFile -isnot [System.IO.FileInfo])
  {
    throw "Octopus.Server.exe path '$OctopusServerExePath ' does not refer to a file."
  }

  $fileVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($OctopusServerExePath).FileVersion
  $octopusServerVersion = New-Object System.Version $fileVersion
  $versionWhereShowConfigurationWasIntroduced = New-Object System.Version 3, 5, 0

  if ($octopusServerVersion -ge $versionWhereShowConfigurationWasIntroduced) {
    $rawConfig = & $OctopusServerExePath show-configuration --format=json-hierarchical --noconsolelogging --console
    $config = $rawConfig | ConvertFrom-Json

    $result = [pscustomobject] @{
      OctopusStorageExternalDatabaseConnectionString         = $config.Octopus.Storage.ExternalDatabaseConnectionString
      OctopusWebPortalListenPrefixes                         = $config.Octopus.WebPortal.ListenPrefixes
      OctopusWebPortalForceSsl                               = [System.Convert]::ToBoolean($config.Octopus.WebPortal.ForceSSL)
      OctopusUpgradesAllowChecking                           = [System.Convert]::ToBoolean($config.Octopus.Upgrades.AllowChecking)
      OctopusUpgradesIncludeStatistics                       = [System.Convert]::ToBoolean($config.Octopus.Upgrades.IncludeStatistics)
      OctopusCommunicationsServicesPort                      = $config.Octopus.Communications.ServicesPort
    }
  }
  else {
    $xml = New-Object xml
    try
    {
      $xml.Load($file.FullName)
    }
    catch
    {
      throw
    }

    $result = [pscustomobject] @{
      OctopusStorageExternalDatabaseConnectionString         = $xml.SelectSingleNode('/octopus-settings/set[@key="Octopus.Storage.ExternalDatabaseConnectionString"]/text()').Value
      OctopusWebPortalListenPrefixes                         = $xml.SelectSingleNode('/octopus-settings/set[@key="Octopus.WebPortal.ListenPrefixes"]/text()').Value
      OctopusWebPortalForceSsl                               = [System.Convert]::ToBoolean($xml.SelectSingleNode('/octopus-settings/set[@key="Octopus.WebPortal.ForceSsl"]/text()').Value)
      OctopusUpgradesAllowChecking                           = [System.Convert]::ToBoolean($xml.SelectSingleNode('/octopus-settings/set[@key="Octopus.Upgrades.AllowChecking"]/text()').Value)
      OctopusUpgradesIncludeStatistics                       = [System.Convert]::ToBoolean($xml.SelectSingleNode('/octopus-settings/set[@key="Octopus.Upgrades.IncludeStatistics"]/text()').Value)
      OctopusCommunicationsServicesport                      = $xml.SelectSingleNode('/octopus-settings/set[@key="Octopus.Communications.ServicesPort"]/text()').Value
    }
  }
  return $result
}

function Set-TargetResource
{
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSDSCUseVerboseMessageInDSCResource", "The Write-Verbose calls are in other methods")]
  param (
    [ValidateSet("Present", "Absent")]
    [string]$Ensure = "Present",
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Name,
    [ValidateSet("Started", "Stopped")]
    [string]$State = "Started",
    [ValidateNotNullOrEmpty()]
    [string]$DownloadUrl = "https://octopus.com/downloads/latest/WindowsX64/OctopusServer",
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$WebListenPrefix,
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$SqlDbConnectionString,
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$OctopusAdminUsername,
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$OctopusAdminPassword,
    [bool]$UpgradeCheck = $true,
    [bool]$UpgradeCheckWithStatistics = $true,
    [string]$WebAuthenticationMode = 'UsernamePassword',
    [bool]$ForceSSL = $false,
    [int]$ListenPort = 10943
  )

  if ($Ensure -eq "Absent" -and $State -eq "Started")
  {
    throw "Invalid configuration requested. " + `
          "You have asked for the service to not exist, but also be running at the same time. " +`
          "You probably want 'State = `"Stopped`"."
  }

  $currentResource = (Get-TargetResource -Ensure $Ensure `
                                         -Name $Name `
                                         -State $State `
                                         -DownloadUrl $DownloadUrl `
                                         -WebListenPrefix $WebListenPrefix `
                                         -SqlDbConnectionString $SqlDbConnectionString `
                                         -OctopusAdminUsername $OctopusAdminUsername `
                                         -OctopusAdminPassword $OctopusAdminPassword `
                                         -UpgradeCheck $UpgradeCheck `
                                         -UpgradeCheckWithStatistics $UpgradeCheckWithStatistics `
                                         -WebAuthenticationMode $WebAuthenticationMode `
                                         -ForceSSL $ForceSSL `
                                         -ListenPort $ListenPort)

  if ($State -eq "Stopped" -and $currentResource["State"] -eq "Started")
  {
    Stop-OctopusDeployService $Name
  }

  if ($Ensure -eq "Absent" -and $currentResource["Ensure"] -eq "Present")
  {
    Uninstall-OctopusDeploy $Name
  }
  elseif ($Ensure -eq "Present" -and $currentResource["Ensure"] -eq "Absent")
  {
    Install-OctopusDeploy -name $Name `
                          -downloadUrl $DownloadUrl `
                          -webListenPrefix $WebListenPrefix `
                          -sqlDbConnectionString $SqlDbConnectionString `
                          -OctopusAdminUsername $OctopusAdminUsername `
                          -OctopusAdminPassword $OctopusAdminPassword `
                          -upgradeCheck $upgradeCheck `
                          -upgradeCheckWithStatistics $upgradeCheckWithStatistics `
                          -webAuthenticationMode $webAuthenticationMode `
                          -forceSSL $forceSSL `
                          -listenPort $listenPort
  }
  elseif ($Ensure -eq "Present" -and $currentResource["DownloadUrl"] -ne $DownloadUrl)
  {
    Update-OctopusDeploy $Name $DownloadUrl $State
  }

  $params = Get-Parameters $MyInvocation.MyCommand.Parameters
  if (Test-ReconfigurationRequired $currentResource $params)
  {
    Set-OctopusDeployConfiguration -name $Name `
                                   -webListenPrefix $WebListenPrefix `
                                   -upgradeCheck $UpgradeCheck `
                                   -UpgradeCheckWithStatistics $UpgradeCheckWithStatistics `
                                   -webAuthenticationMode $WebAuthenticationMode `
                                   -forceSSL $ForceSSL `
                                   -listenPort $ListenPort
  }

  if ($State -eq "Started" -and $currentResource["State"] -eq "Stopped")
  {
    Start-OctopusDeployService $Name
  }
}

function Set-OctopusDeployConfiguration
{
  param (
    [Parameter(Mandatory=$True)]
    [string]$name,
    [Parameter(Mandatory=$True)]
    [string]$webListenPrefix,
    [Parameter(Mandatory)]
    [bool]$upgradeCheck = $true,
    [bool]$upgradeCheckWithStatistics = $true,
    [string]$webAuthenticationMode = 'UsernamePassword',
    [bool]$forceSSL = $false,
    [int]$listenPort = 10943
  )

  Write-Log "Configuring Octopus Deploy instance ..."
  $args = @(
    'configure',
    '--console',
    '--instance', $name,
    '--upgradeCheck', $upgradeCheck,
    '--upgradeCheckWithStatistics', $upgradeCheckWithStatistics,
    '--webAuthenticationMode', $webAuthenticationMode,
    '--webForceSSL', $forceSSL,
    '--webListenPrefixes', $webListenPrefix,
    '--commsListenPort', $listenPort
  )
  Invoke-OctopusServerCommand $args
}

function Test-ReconfigurationRequired($currentState, $desiredState)
{
  $reconfigurableProperties = @('ListenPort', 'WebListenPrefix', 'ForceSSL', 'UpgradeCheckWithStatistics', 'UpgradeCheck')
  foreach($property in $reconfigurableProperties)
  {
    if ($currentState.Item($property) -ne ($desiredState.Item($property)))
    {
      return $true
    }
  }
  return $false
}

function Uninstall-OctopusDeploy($name)
{
  $serviceName = (Get-ServiceName $name)
  Write-Verbose "Deleting service $serviceName..."
  $services = @(Get-CimInstance win32_service | Where-Object {$_.PathName -like "`"$($env:ProgramFiles)\Octopus Deploy\Octopus\Octopus.Server.exe*"})
  Invoke-AndAssert { & sc.exe delete $serviceName }

  if ($services.length -eq 1)
  {
    # Uninstall msi
    Write-Verbose "Uninstalling Octopus..."
    if (-not (Test-Path "$($env:SystemDrive)\Octopus\logs")) { New-Item -type Directory "$($env:SystemDrive)\Octopus\logs" | out-null }
    $msiPath = "$($env:SystemDrive)\Octopus\Octopus-x64.msi"
    $msiLog = "$($env:SystemDrive)\Octopus\logs\Octopus-x64.msi.uninstall.log"
    if (Test-Path $msiPath)
    {
      $msiExitCode = (Start-Process -FilePath "msiexec.exe" -ArgumentList "/x $msiPath /quiet /l*v $msiLog" -Wait -Passthru).ExitCode
      Write-Verbose "MSI uninstaller returned exit code $msiExitCode"
      if ($msiExitCode -ne 0)
      {
        throw "Removal of Octopus Server failed, MSIEXEC exited with code: $msiExitCode. View the log at $msiLog"
      }
    }
    else
    {
      throw "Octopus Server cannot be removed, because the MSI could not be found."
    }
  }
  else
  {
    Write-Verbose "Skipping uninstall, as other instances still exist:"
    foreach($otherService in $otherServices)
    {
      Write-Verbose " - $($otherService.Name)"
    }
  }
}

function Update-OctopusDeploy($name, $downloadUrl, $state)
{
  Write-Verbose "Upgrading Octopus Deploy..."
  $serviceName = (Get-ServiceName $name)
  Stop-Service -Name $serviceName
  Install-MSI $downloadUrl
  if ($state -eq "Started") {
    Start-Service $serviceName
  }
  Write-Verbose "Octopus Deploy upgraded!"
}

function Start-OctopusDeployService($name)
{
  $serviceName = (Get-ServiceName $Name)
  Write-Verbose "Starting $serviceName"
  Start-Service -Name $serviceName
}

function Stop-OctopusDeployService($name)
{
  $serviceName = (Get-ServiceName $Name)
  Write-Verbose "Stopping $serviceName"
  Stop-Service -Name $serviceName -Force
}

function Get-ServiceName
{
    param ( [string]$instanceName )

    if ($instanceName -eq "OctopusServer")
    {
        return "OctopusDeploy"
    }
    else
    {
        return "OctopusDeploy: $instanceName"
    }
}

function Install-MSI
{
    param (
        [string]$downloadUrl
    )
    Write-Verbose "Beginning installation"

    mkdir "$($env:SystemDrive)\Octopus" -ErrorAction SilentlyContinue

    $msiPath = "$($env:SystemDrive)\Octopus\Octopus-x64.msi"
    if ((Test-Path $msiPath) -eq $true)
    {
        Remove-Item $msiPath -force
    }
    Write-Verbose "Downloading Octopus MSI from $downloadUrl to $msiPath"
    Request-File $downloadUrl $msiPath

    Write-Verbose "Installing MSI..."
    if (-not (Test-Path "$($env:SystemDrive)\Octopus\logs")) { New-Item -type Directory "$($env:SystemDrive)\Octopus\logs" }
    $msiLog = "$($env:SystemDrive)\Octopus\logs\Octopus-x64.msi.log"
    $msiExitCode = (Start-Process -FilePath "msiexec.exe" -ArgumentList "/i $msiPath /quiet /l*v $msiLog" -Wait -Passthru).ExitCode
    Write-Verbose "MSI installer returned exit code $msiExitCode"
    if ($msiExitCode -ne 0)
    {
        throw "Installation of the MSI failed; MSIEXEC exited with code: $msiExitCode. View the log at $msiLog"
    }

    Update-InstallState "DownloadUrl" $downloadUrl
}

function Update-InstallState
{
  param (
    [string]$key,
    [string]$value
  )

  $currentInstallState = @{}
  if (Test-Path $installStateFile) {
    $fileContent = (Get-Content -Raw -Path $installStateFile | ConvertFrom-Json)
    $fileContent.psobject.properties | ForEach-Object { $currentInstallState[$_.Name] = $_.Value }
  }

  $currentInstallState.Set_Item($key, $value)

  $currentInstallState | ConvertTo-Json | set-content $installStateFile
}

function Request-File
{
    param (
        [string]$url,
        [string]$saveAs
    )

    Write-Verbose "Downloading $url to $saveAs"
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12,[System.Net.SecurityProtocolType]::Tls11,[System.Net.SecurityProtocolType]::Tls
    $downloader = new-object System.Net.WebClient
    try {
      $downloader.DownloadFile($url, $saveAs)
    }
    catch
    {
       throw $_.Exception.InnerException
    }
}

function Write-Log
{
  param (
    [string] $message
  )

  $timestamp = ([System.DateTime]::UTCNow).ToString("yyyy'-'MM'-'dd'T'HH':'mm':'ss")
  Write-Verbose "[$timestamp] $message"
}

function Invoke-AndAssert {
    param ($block)

    & $block | Write-Verbose
    if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE)
    {
        throw "Command returned exit code $LASTEXITCODE"
    }
}

function Install-OctopusDeploy
{
  param (
    [Parameter(Mandatory=$True)]
    [string]$name,
    [Parameter(Mandatory=$True)]
    [string]$downloadUrl,
    [Parameter(Mandatory=$True)]
    [string]$webListenPrefix,
    [Parameter(Mandatory=$True)]
    [string]$sqlDbConnectionString,
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$octopusAdminUsername,
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$octopusAdminPassword,
    [bool]$upgradeCheck = $true,
    [bool]$upgradeCheckWithStatistics = $true,
    [string]$webAuthenticationMode = 'UsernamePassword',
    [bool]$forceSSL = $false,
    [int]$listenPort = 10943
  )

  Write-Verbose "Installing Octopus Deploy..."
  Write-Log "Setting up new instance of Octopus Deploy with name '$name'"
  Install-MSI $downloadUrl

  Write-Log "Creating Octopus Deploy instance ..."
  $args = @(
    'create-instance',
    '--console',
    '--instance', $name,
    '--config', "$($env:SystemDrive)\Octopus\OctopusServer.config"
  )
  Invoke-OctopusServerCommand $args

  Write-Log "Configuring Octopus Deploy instance ..."
  $args = @(
    'configure',
    '--console',
    '--instance', $name,
    '--home', "$($env:SystemDrive)\Octopus",
    '--upgradeCheck', $upgradeCheck,
    '--upgradeCheckWithStatistics', $upgradeCheckWithStatistics,
    '--webAuthenticationMode', $webAuthenticationMode,
    '--webForceSSL', $forceSSL,
    '--webListenPrefixes', $webListenPrefix,
    '--commsListenPort', $listenPort,
    '--storageConnectionString', $sqlDbConnectionString
  )
  Invoke-OctopusServerCommand $args

  Write-Log "Creating Octopus Deploy database ..."
  $args = @(
    'database',
    '--console',
    '--instance', $name,
    '--create'
  )
  Invoke-OctopusServerCommand $args

  Write-Log "Stopping Octopus Deploy instance ..."
  $args = @(
    'service',
    '--console',
    '--instance', $name,
    '--stop'
  )
  Invoke-OctopusServerCommand $args

  Write-Log "Creating Admin User for Octopus Deploy instance ..."
  $args = @(
    'admin',
    '--console',
    '--instance', $name,
    '--username', $octopusAdminUsername,
    '--password', $octopusAdminPassword
  )
  Invoke-OctopusServerCommand $args
  Update-InstallState "OctopusAdminUsername" $octopusAdminUsername
  Update-InstallState "OctopusAdminPassword" (Get-EncryptedString $octopusAdminPassword)

  Write-Log "Configuring Octopus Deploy instance to use free license ..."
  $args = @(
    'license',
    '--console',
    '--instance', $name,
    '--free'
  )
  Invoke-OctopusServerCommand $args

  Write-Log "Install Octopus Deploy service ..."
  $args = @(
    'service',
    '--console',
    '--instance', $name,
    '--install',
    '--reconfigure',
    '--stop'
  )
  Invoke-OctopusServerCommand $args
  Write-Verbose "Octopus Deploy installed!"
}

function Get-EncryptedString($string)
{
  return $string | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString
}

function Get-DecryptedSecureString($encryptedString)
{
  $secureString = ConvertTo-SecureString -string $encryptedString
  $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureString)
  return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
}

function Invoke-OctopusServerCommand ($arguments)
{
  $exe = "$($env:ProgramFiles)\Octopus Deploy\Octopus\Octopus.Server.exe"
  Write-Log "Executing command '$exe $($arguments -join ' ')'"
  $output = .$exe $arguments

  Write-CommandOutput $output
  if (($null -ne $LASTEXITCODE) -and ($LASTEXITCODE -ne 0)) {
    Write-Error "Command returned exit code $LASTEXITCODE. Aborting."
    exit 1
  }
  Write-Log "done."
}

function Write-CommandOutput
{
  param (
    [string] $output
  )

  if ($output -eq "") { return }

  Write-Verbose ""
  #this isn't quite working
  foreach($line in $output.Trim().Split("`n"))
  {
    Write-Verbose $line
  }
  Write-Verbose ""
}

function Test-TargetResource
{
  param (
    [ValidateSet("Present", "Absent")]
    [string]$Ensure = "Present",
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Name,
    [ValidateSet("Started", "Stopped")]
    [string]$State = "Started",
    [ValidateNotNullOrEmpty()]
    [string]$DownloadUrl = "https://octopus.com/downloads/latest/WindowsX64/OctopusServer",
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$WebListenPrefix,
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$SqlDbConnectionString,
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$OctopusAdminUsername,
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$OctopusAdminPassword,
    [bool]$UpgradeCheck = $true,
    [bool]$UpgradeCheckWithStatistics = $true,
    [string]$WebAuthenticationMode = 'UsernamePassword',
    [bool]$ForceSSL = $false,
    [int]$ListenPort = 10943
  )

  $currentResource = (Get-TargetResource -Ensure $Ensure `
                                         -Name $Name `
                                         -State $State `
                                         -DownloadUrl $DownloadUrl `
                                         -WebListenPrefix $WebListenPrefix `
                                         -SqlDbConnectionString $SqlDbConnectionString `
                                         -OctopusAdminUsername $OctopusAdminUsername `
                                         -OctopusAdminPassword $OctopusAdminPassword `
                                         -UpgradeCheck $UpgradeCheck `
                                         -UpgradeCheckWithStatistics $UpgradeCheckWithStatistics `
                                         -WebAuthenticationMode $WebAuthenticationMode `
                                         -ForceSSL $ForceSSL `
                                         -ListenPort $ListenPort)

  $params = Get-Parameters $MyInvocation.MyCommand.Parameters

  $currentConfigurationMatchesRequestedConfiguration = $true
  foreach($key in $currentResource.Keys)
  {
    $currentValue = $currentResource.Item($key)
    $requestedValue = $params.Item($key)
    if ($key -eq "OctopusAdminPassword")
    {
      if ((Get-DecryptedSecureString $currentValue) -ne $requestedValue)
      {
        Write-Verbose "(FOUND MISMATCH) Configuration parameter '$key' with value '********' mismatched the specified value '********'"
        $currentConfigurationMatchesRequestedConfiguration = $false
      }
      else
      {
        Write-Verbose "Configuration parameter '$key' matches the requested value '********'"
      }
    }
    elseif ($currentValue -ne $requestedValue)
    {
      Write-Verbose "(FOUND MISMATCH) Configuration parameter '$key' with value '$currentValue' mismatched the specified value '$requestedValue'"
      $currentConfigurationMatchesRequestedConfiguration = $false
    }
    else
    {
      Write-Verbose "Configuration parameter '$key' matches the requested value '$requestedValue'"
    }
  }

  return $currentConfigurationMatchesRequestedConfiguration
}

function Get-Parameters($parameters)
{
  # unfortunately $PSBoundParameters doesn't contain parameters that weren't supplied (because the default value was okay)
  # credit to https://www.briantist.com/how-to/splatting-psboundparameters-default-values-optional-parameters/
  $params = @{}
  foreach($h in $parameters.GetEnumerator()) {
    $key = $h.Key
    $var = Get-Variable -Name $key -ErrorAction SilentlyContinue
    if ($null -ne $var)
    {
      $val = Get-Variable -Name $key -ErrorAction Stop | Select-Object -ExpandProperty Value -ErrorAction Stop
      $params[$key] = $val
    }
  }
  return $params
}