#requires -Version 7.0
#requires -Modules Az.Account
[CmdLetBinding()]
param(
    [Parameter(HelpMessage="The id of the subscription where the APIM resides. Defaults to the context subscription.")]
    [string]$SubscriptionId,
    [Parameter(Mandatory=$true, HelpMessage="The name of the resource group where the APIM resides.")]
    [string]$ResourceGroupName,
    [Parameter(Mandatory=$true, HelpMessage="The name of the API Management resource.")]
    [string]$ApimName,
    [Parameter(Mandatory=$true, HelpMessage="The name of the API to get debug logs for.")]
    [string]$ApiName
)

try {
    $context = Get-AzContext
    if ($null -eq $context) {
        Connect-AzAccount
    }
}
catch {
    throw "Failed to connect to Azure. Please run 'Connect-AzAccount' to login to your Azure account."
}

try {
    if ([string]::IsNullOrWhiteSpace($SubscriptionId)) {
        $SubscriptionId = $context.Subscription.Id
    }

    $apimResourceId = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.ApiManagement/service/$ApimName"
    $at = Get-AzAccessToken -ResourceUrl "https://management.azure.com/" -AsSecureString
    $accessToken = $at.Token | ConvertFrom-SecureString -AsPlainText

    $ApiResourceId = "$apimResourceId/apis/{0}" -f $ApiName

    $credentialsBody = @{
        "credentialsExpireAfter" = "PT1H"
        "apiId" = $ApiResourceId
        "purposes" = @("tracing")
    } | ConvertTo-Json

    $credentialsResponse = Invoke-WebRequest -Uri "$apimResourceId/gateways/managed/listDebugCredentials?api-version=2023-05-01-preview" `
                                            -Method POST `
                                            -Headers @{"Authorization"="Bearer $AccessToken"} `
                                            -Body $credentialsBody `
                                            -ContentType "application/json"
    $apimDebugToken = ($credentialsResponse.Content | ConvertFrom-Json).token
    $tok = @{ Header = "Apim-Debug-Authorization"; Token = $apimDebugToken }
    Write-Host $tok | Format-List

    Write-Host "Be sure to include the Apim-Debug-Authorization header in your request to the API you want to debug with the value of the token." -ForegroundColor Yellow
}
catch {
    Write-Error "An exception occured while performing the operation: $($_.Exception)"
}