#Requires -Version 5.1

<#
.SYNOPSIS
  Replaces the SSL Certificate of an App Service using a certificate from the Key Vault
.DESCRIPTION
  Set-AzAppServiceCertificate is a PowerShell function that replaces the certificate in an App Service with the one specified from the Key Vault
.PARAMETER ResourceGroupName
    Specifies the name of the resource group that the certificate is assigned to
.PARAMETER VaultResourceGroupName
    Specifies the name of the resource group that the key vault is assigned to. You cannot use the VaultResourceGroupName parameter and the Vault parameter in the same command.
.PARAMETER AppServiceName
    Specifies the name of the app service that the certificate will be assigned to. You cannot use the AppServiceName parameter and the AppService parameter in the same command.
.PARAMETER AppService
    Specifies the app service that the certificate will be assigned to. You cannot use the AppServiceName parameter and the AppService parameter in the same command.
.PARAMETER Name
    Specifies the name of the certificate
.PARAMETER VaultName
    Specifies the name of the key vault. You cannot use the VaultName parameter and the Vault parameter in the same command.
.PARAMETER Vault
    Specifies the key vault that contains the certificate. You cannot use the VaultName parameter and the Vault parameter in the same command.
.PARAMETER VaultCertificateName
    Specifies the name of the key vault certificate
.INPUTS
  None
.OUTPUTS
  None
.NOTES
  Version:        1.0
  Author:         Dominique St-Amand
  Creation Date:  2019-10-12
  Purpose/Change: Initial script development
.EXAMPLE
  Set-AzAppServiceCertificate -ResourceGroupName "ContosoRG" -AppServiceName "ASP-Contoso" -VaultResourceGroupName "ContosoRG" -VaultName "ContosoKV" -VaultCertificateName "ContosoWildcard" -Name "contosokv-contoso-wildcard"
.EXAMPLE
  $Vault = Get-AzKeyVault -ResourceGroupName "ContosoRG" -VaultName "ContosoKV"
  Set-AzAppServiceCertificate -ResourceGroupName "ContosoRG" -Vault $Vault -AppServiceName "ASP-Contoso" -VaultCertificateName "ContosoWildcard"-Name "contosokv-contoso-wildcard"
.EXAMPLE
  $AppService = Get-AzAppServicePlan -ResourceGroupName "ContosoRG" -Name "ASP-Contoso"
  Set-AzAppServiceCertificate -ResourceGroupName "ContosoRG" -VaultResourceGroupName "ContosoRG" -VaultName "ContosoKV" -AppService $AppService -VaultCertificateName "ContosoWildcard" -Name "contosokv-contoso-wildcard"
.EXAMPLE
  $Vault = Get-AzKeyVault -ResourceGroupName "ContosoRG" -VaultName "ContosoKV"
  $AppService = Get-AzAppServicePlan -ResourceGroupName "ContosoRG" -Name "ASP-Contoso"
  Set-AzAppServiceCertificate -ResourceGroupName "ContosoRG" -Vault $Vault -AppService $AppService -VaultCertificateName "ContosoWildcard" -Name "contosokv-contoso-wildcard"
#>

[CmdletBinding()]
Param (
    [Parameter(Mandatory=$True)]
    [string] $ResourceGroupName,
    [Parameter()]
    [string] $VaultResourceGroupName,    
    [Parameter()]
    [string] $AppServiceName,
    [Parameter()]
    [Microsoft.Azure.Commands.WebApps.Models.WebApp.PSAppServicePlan] $AppService,    
    [Parameter(Mandatory=$True)]
    [string] $Name,
    [Parameter()]
    [string] $VaultName,
    [Parameter()]
    [Microsoft.Azure.Commands.KeyVault.Models.PSKeyVault] $Vault,    
    [Parameter(Mandatory=$True)]
    [string] $VaultCertificateName
)

if ($AppServiceName -and $AppService) {
    throw "You cannot use the AppServiceName parameter and the AppService parameter in the same command."
}

if ($VaultName -and $Vault) {
    throw "You cannot use the VaultName parameter and the Vault parameter in the same command."
}

if ($VaultResourceGroupName -and $Vault) {
    throw "You cannot use the VaultResourceGroupName parameter and the Vault parameter in the same command."
}

if (!($Vault) -and (!($VaultName) -or !($VaultResourceGroupName))) {
    throw "VaultName or VaultResourceGroupName parameter is missing."
}

if (!($AppServiceName) -and $AppService) {
    $ServerFarmId = $AppService.Id
}
else {
    $ServerFarmId = (Get-AzAppServicePlan -ResourceGroupName $ResourceGroupName -Name $AppServiceName).Id
}

if ($Vault) {
    $VaultName = $Vault.VaultName
    $KeyVaultId = $Vault.ResourceId
}
else {
    $Vault = Get-AzKeyVault -ResourceGroupName $VaultResourceGroupName -VaultName $VaultName
    $KeyVaultId = $Vault.ResourceId
}

$MicrosoftAzureAppServiceObjectId = "abfa0a7c-a6b6-4736-8310-5855508787cd"
Set-AzKeyVaultAccessPolicy -VaultName $VaultName -ServicePrincipalName $MicrosoftAzureAppServiceObjectId -PermissionsToSecrets get -PermissionsToCertificates get

$Resource = Get-AzResource -ResourceType Microsoft.web/certificates -ResourceGroupName $ResourceGroupName -ResourceName $Name
$Resource.Properties.keyVaultId = $KeyVaultId
$Resource.Properties.keyVaultSecretName = $VaultCertificateName
$Resource.Properties.serverFarmId = $ServerFarmId
$Resource | Set-AzResource -Force