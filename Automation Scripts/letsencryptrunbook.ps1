#Requires -Version 5.1
#Requires -Modules @{ ModuleName="ACME-PS"; ModuleVersion="1.1.0" }

<#
.SYNOPSIS
    Generates a SSL certificate from Let's Encrypt and saves it into a key vault.
.DESCRIPTION
    Generates a SSL certificate from Let's Encrypt and saves it into a key vault.
    The script assumes a DNZ Zone resource exists for the Dns you are trying to generate a certificate for.
    It also assumes you already have a storage account and a blob container created.
.PARAMETER ResourceGroupName
    Specifies the resource group name where the storage account, key vault and dns reside.
.PARAMETER StorageAccountName
    Specifies the storage account name to use to store the state of the letsencrypt account(s).
.PARAMETER ContactEmails
    Specifies the contact emails to use when creating a new lets encrypt account is created.
.PARAMETER DnsName
    Specifies the dns that a certificate needs to be created for.
    For wildcards, use *.hostname.tld
.PARAMETER KeyVaultName
    Specifies the name of the keyvault where the certificate will be stored.
.PARAMETER StorageContainerName
    Specifies the name of the container in the blob storage where the state data is stored. Defaults to letsencrypt.
.PARAMETER KeyVaultCertificateSecretName
    Specifies the key vault secret name of the certificate password that will be used to export the certificate once it has been issued by Let's Encrypt.
.PARAMETER Test
    Specifies whether to use lets encrypt staging/test facily or production facility.
.PARAMETER VerboseOutput
    Specifies whether to set the VerbosePreference to continue
#>

[CmdletBinding()]
Param (
    [Parameter(Mandatory=$True)]
    [string] $ResourceGroupName,    
    [Parameter(Mandatory=$True)]
    [string] $StorageAccountName,
    [Parameter(Mandatory=$True)]
    [string[]] $ContactEmails,
    [Parameter(Mandatory=$True)]
    [string] $DnsName, 
    [Parameter(Mandatory=$True)]
    [string] $KeyVaultName,
    [Parameter()]
    [string] $StorageContainerName = "letsencrypt",
    [Parameter(Mandatory=$True)]
    [string] $KeyVaultCertificateSecretName,    
    [Parameter()]
    [bool] $Test = $false,
    [Parameter()]
    [bool] $VerboseOutput = $false    
)

$ErrorActionPreference = 'stop'
if ($VerboseOutput) {
    $VerbosePreference = 'continue'
}

function Add-DirectoryToAzureStorage {
    Param (
        [Parameter(Mandatory=$true)]
        [string] $Path,
        [Parameter(Mandatory=$true)]
        [string] $StorageAccountName,
        [Parameter(Mandatory=$true)]
        [string] $StorageAccountKey,        
        [Parameter(Mandatory=$true)]
        [string] $ContainerName
    )

    if ([string]::IsNullOrWhiteSpace($StorageAccountKey)) {
        $context = New-AzStorageContext -StorageAccountName $StorageAccountName -UseConnectedAccount
    }
    else {
        $context = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey
    }

    $items = Get-ChildItem -Path $Path -File -Recurse
    $startIndex = $Path.Length + 1
    foreach ($item in $items) {
        $targetPath = ($item.FullName.Substring($startIndex)).Replace("\", "/")
        Set-AzStorageBlobContent -File $item.FullName -Container $ContainerName -Context $context -Blob $targetPath -Force | Out-Null
    }
}

function Get-DirectoryFromAzureStorage {
    Param (
        [Parameter(Mandatory=$true)]
        [string] $DestinationPath,
        [Parameter(Mandatory=$true)]
        [string] $StorageAccountName,
        [Parameter(Mandatory=$true)]
        [string] $StorageAccountKey,        
        [Parameter(Mandatory=$true)]
        [string] $ContainerName,
        [Parameter()]
        [string] $BlobName        
    )

    if ([string]::IsNullOrWhiteSpace($StorageAccountKey)) {
        $context = New-AzStorageContext -StorageAccountName $StorageAccountName
    }
    else {
        $context = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey
    }

    if ([string]::IsNullOrWhiteSpace($BlobName)) {
        $items = Get-AzStorageBlob -Container $ContainerName -Context $context
    }
    else {
        $items = Get-AzStorageBlob -Container $ContainerName -Blob $BlobName -Context $context
    }

    if ((Test-Path $DestinationPath) -eq $FALSE) {
        New-Item -Path $DestinationPath -ItemType Directory | Out-Null
    }

    foreach ($item in $items) {
        Get-AzStorageBlobContent -Container $ContainerName -Blob $item.Name -Destination $DestinationPath -Context $context -Force | Out-Null
    }
}

function New-AccountProvisioning {
    Param (
        [Parameter(Mandatory=$True)]
        [string] $StateDir,
        [Parameter(Mandatory=$True)]
        [string[]] $ContactEmails,
        [Parameter()]
        [switch] $Test            
    )
    
    if ($Test) {
        $serviceName = "LetsEncrypt-Staging"
    }
    else {
        $serviceName = "LetsEncrypt"
    }

    # Create a state object and save it to the harddrive
    $state = New-ACMEState -Path $StateDir

    # Fetch the service directory and save it in the state
    Get-ACMEServiceDirectory $state -ServiceName $serviceName

    # Get the first anti-replay nonce
    New-ACMENonce $state

    # Create an account key. The state will make sure it's stored.
    New-ACMEAccountKey $state

    # Register the account key with the acme service. The account key will automatically be read from the state
    New-ACMEAccount $state -EmailAddresses $ContactEmails -AcceptTOS

    return $state
}

function Get-SubDomainFromHostname {
    Param (
        [Parameter(Mandatory=$true)]
        [string] $Hostname
    )

    $splitDomainParts = $Hostname -split "\."
    $subDomain = ""
    for ($i =0; $i -lt $splitDomainParts.Length-2; $i++) {
        $subDomain += "{0}." -f $splitDomainParts[$i]
    }
    return $subDomain.SubString(0,$subDomain.Length-1)
}    

function Add-TxtRecordToDns {
    Param (
        [Parameter(Mandatory=$True)]
        [string] $ResourceGroupName,
        [Parameter(Mandatory=$True)]
        [string] $DnsZoneName,           
        [Parameter(Mandatory=$True)]
        [string] $TxtName,
        [Parameter(Mandatory=$True)]
        [string] $TxtValue,
        [switch] $IsWildcard
    )

    $subDomain = Get-SubDomainFromHostname -Hostname $TxtName

    New-AzDnsRecordSet -ResourceGroupName $ResourceGroupName `
                        -ZoneName $DnsZoneName `
                        -Name $subDomain `
                        -RecordType TXT `
                        -Ttl 10 `
                        -DnsRecords (New-AzDnsRecordConfig -Value $TxtValue)        
}

function Remove-TxtRecordToDns {
    Param (
        [Parameter(Mandatory=$True)]
        [string] $ResourceGroupName,
        [Parameter(Mandatory=$True)]
        [string] $DnsZoneName,           
        [Parameter(Mandatory=$True)]
        [string] $TxtName,
        [switch] $IsWildcard
    )

    $subDomain = Get-SubDomainFromHostname -Hostname $TxtName

    $recordSet = Get-AzDnsRecordSet -ResourceGroupName $ResourceGroupName `
                                    -ZoneName $DnsZoneName `
                                    -Name $subDomain `
                                    -RecordType TXT

    Remove-AzDnsRecordSet -RecordSet $recordSet -Confirm:$False -Overwrite
}

try {
        # Ensures that any credentials apply only to the execution of this runbook
        Disable-AzContextAutosave -Scope Process | Out-Null
        
        # Connect to Azure with RunAs account
        $servicePrincipalConnection = Get-AutomationConnection -Name AzureRunAsConnection

        $logonAttempt = 0
        $logonResult = $False
        
        while(!($connectionResult) -and ($logonAttempt -le 10)) {
            $LogonAttempt++
            # Logging in to Azure...
            Write-Output "Connecting to Azure..."
            $connectionResult = Connect-AzAccount `
                                -ServicePrincipal `
                                -TenantId $servicePrincipalConnection.TenantId `
                                -ApplicationId $servicePrincipalConnection.ApplicationId `
                                -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint
        
            if ($connectionResult) {
                $logonResult = $true
            }
            Start-Sleep -Seconds 30
        }    

        if ($logonResult -eq $false) {
            Write-Error -Message "Unable to sign in using the automation service principal account after 10 attempts"
            return
        }

        Write-Output "Connected to Azure"

        $mainDir = Join-Path $env:TEMP "LetsEncrypt"
        if ($Test) {
            $stateDir = Join-Path $mainDir "Staging"
        }
        else {
            $stateDir = Join-Path $mainDir "Prod"
        }

        $keyVaultCertificateName = (($DnsName.Replace("*","wildcard")).Replace(".","-")).ToLowerInvariant()
        if ($Test) {
            $keyVaultCertificateName += "-test"
        }

        $keyVaultSecretValue = (Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $KeyVaultCertificateSecretName).SecretValueText
        $certificatePassword = ConvertTo-SecureString $keyVaultSecretValue -AsPlainText -Force

        $storageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $StorageAccountName | Where-Object { $_.KeyName -eq "key1" } | Select-Object Value).Value

        Write-Output "Fetching the state directory from storage"
        if($Test) {
            Get-DirectoryFromAzureStorage -DestinationPath $mainDir `
                                        -StorageAccountName $StorageAccountName `
                                        -StorageAccountKey $storageAccountKey `
                                        -ContainerName $StorageContainerName `
                                        -BlobName "Staging/*"
        }
        else {
            Get-DirectoryFromAzureStorage -DestinationPath $mainDir `
                                            -StorageAccountName $StorageAccountName `
                                            -StorageAccountKey $storageAccountKey `
                                            -ContainerName $StorageContainerName `
                                            -BlobName "Prod/*"
        }

        $isNew = (Test-Path $stateDir) -eq $false
        if ($isNew) {
            Write-Output "Directory is empty. Adding a new account"
            $state = New-AccountProvisioning -StateDir $stateDir -ContactEmails $ContactEmails -Test:$Test
            
            Write-Output "Saving the state directory to storage"
            Add-DirectoryToAzureStorage -Path $mainDir `
                                        -StorageAccountName $StorageAccountName `
                                        -StorageAccountKey $storageAccountKey `
                                        -ContainerName $StorageContainerName
        }
        else { 
            # Load an state object to have service directory and account keys available
            $state = Get-ACMEState -Path $stateDir
        }

        # It might be neccessary to acquire a new nonce, so we'll just do it for the sake.
        Write-Output "Acquring new nonce"
        New-ACMENonce $state

        # Create the identifier for the DNS name
        $identifier = New-ACMEIdentifier $DnsName

        # Create the order object at the ACME service.
        Write-Output "Creating a new order"
        $order = New-ACMEOrder $state -Identifiers $identifier

        # Fetch the authorizations for that order
        Write-Output "Fetching the authorizations for the order"
        $authZ = Get-ACMEAuthorization -State $state -Order $order

        # Select a challenge to fullfill
        Write-Output "Getting the challenge"
        $challenge = Get-ACMEChallenge $state $authZ "dns-01"

        # Inspect the challenge data
        Write-Output "Dumping the challenge data"
        $challenge.Data

        $challengeTxtRecordName = $challenge.Data.TxtRecordName
        $challengeToken = $challenge.Data.Content

        # Insert the data into the proper TXT record
        $splitDomainParts = $challengeTxtRecordName -split "\."
        $dnsZoneName = "{0}.{1}" -f $splitDomainParts[$splitDomainParts.Length-2], $splitDomainParts[$splitDomainParts.Length-1]
        $isWildcard = $DnsName.StartsWith("*.")

        Write-Output "Adding the txt record"
        Add-TxtRecordToDns -ResourceGroupName $ResourceGroupName `
                            -DnsZoneName $dnsZoneName `
                            -TxtName $challengeTxtRecordName `
                            -TxtValue $challengeToken `
                            -IsWildcard:$isWildcard

        # Signal the ACME server that the challenge is ready
        Write-Output "Signaling the challenge as ready"
        $challenge | Complete-ACMEChallenge $state

        # Wait a little bit and update the order, until we see the states
        while($order.Status -notin ("ready","invalid")) {
            Write-Output "Order is not ready... waiting 10 seconds"
            Start-Sleep -Seconds 10;
            $order | Update-ACMEOrder $state -PassThru
        }

        if ($order.Status -eq "invalid") {
            # ACME-PS as of version 1.0.7 doesn't have the error property. Fetch manually
            $authZWithError = Invoke-RestMethod -Uri $authZ.ResourceUrl
            Write-Error "Order failed. It is in invalid state. Reason: $($authZWithError.challenges.error.detail)"
            return
        }

        # We should have a valid order now and should be able to complete it, therefore we need a certificate key
        Write-Output "Grabbing the certificate key"
        $certificateKeyExportPath = Join-Path $stateDir "$DnsName.key.xml".Replace("*","wildcard")
        if (Test-Path $certificateKeyExportPath) {
            Remove-Item -Path $certificateKeyExportPath
        }
        $certKey = New-ACMECertificateKey -Path $certificateKeyExportPath

        # Complete the order - this will issue a certificate singing request
        Write-Output "Completing the order"
        Complete-ACMEOrder $state -Order $order -CertificateKey $certKey;

        # Now we wait until the ACME service provides the certificate url
        while(-not $order.CertificateUrl) {
            Write-Output "Certificate url is not ready... waiting 15 seconds"
            Start-Sleep -Seconds 15
            $order | Update-Order $state -PassThru
        }

        # As soon as the url shows up we can create the PFX
        Write-Output "Exporting the certificate to the filesystem"
        $certificateExportPath = Join-Path $stateDir "$DnsName.pfx".Replace("*","wildcard")
        Export-ACMECertificate -State $state -Order $order -CertificateKey $certKey -Path $certificateExportPath -Password $certificatePassword

        # Remove the TXT Record
        Write-Output "Removing the TXT record"
        Remove-TxtRecordToDns -ResourceGroupName $ResourceGroupName `
                            -DnsZoneName $dnsZoneName `
                            -TxtName $challengeTxtRecordName `
                            -IsWildcard:$isWildcard

        # Save the certificate into the keyvault
        Write-Output "Adding the certificate to the key vault"
        Import-AzKeyVaultCertificate -VaultName $KeyVaultName -Name $keyVaultCertificateName -FilePath $certificateExportPath -Password $certificatePassword

        # Remove the certificate and key
        Write-Output "Removing the certificate data from the filesystem"
        Remove-Item -Path $certificateExportPath -Force | Out-Null
        Remove-Item -Path $certificateKeyExportPath -Force | Out-Null

		if ($Test -eq $False) {
			Write-Output "Saving the state directory to storage"
			Add-DirectoryToAzureStorage -Path $mainDir `
										-StorageAccountName $StorageAccountName `
										-StorageAccountKey $storageAccountKey `
										-ContainerName $StorageContainerName
		}
}
catch {
    $ErrorMessage = $_.Exception.Message
    Write-Error "An error occurred: $ErrorMessage"
}