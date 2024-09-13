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
    [Parameter(Mandatory=$true, HelpMessage="The debug token for the APIM")]
    [string]$DebugToken,
    [Parameter(Mandatory=$true, HelpMessage="The trace ID for the request. Can be found in the Apim-Trace-Id header of the request that contains the debug token with header Apim-Debug-Authorization.")]
    [string]$TraceId
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

    $body = @{ "traceId" = $TraceId } | ConvertTo-Json
    $logsResponse = Invoke-WebRequest -Uri "$apimResourceId/gateways/managed/listTrace?api-version=2023-05-01-preview" `
                                            -Method POST `
                                            -Headers @{"Authorization"="Bearer $AccessToken"} `
                                            -Body $body `
                                            -ContentType "application/json"
    $logs = $logsResponse.Content | ConvertFrom-Json | ConvertTo-Json -Depth 100
    Write-Host $logs
}
catch {
    Write-Error "An exception occured while performing the operation: $($_.Exception)"
}