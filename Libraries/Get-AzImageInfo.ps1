$location = Get-AzLocation | select displayname | Out-GridView -PassThru -Title "Choose a location"
$publisher = Get-AzVMImagePublisher -Location $location.DisplayName | Out-GridView -PassThru -Title "Choose a publisher"
$offer = Get-AzVMImageOffer -Location $location.DisplayName -PublisherName $publisher.PublisherName | Out-GridView -PassThru -Title "Choose an offer"
$titleSkus = "VM SKUs for {0} {1} {2}" -f $location.DisplayName, $publisher.PublisherName, $offer.Offer
$sku = Get-AzVMImageSku -Location $location.DisplayName -PublisherName $publisher.PublisherName -Offer $offer.Offer | select SKUS | Out-GridView -Title $titleSkus -PassThru
$titleVersions = "VM Versions for {0} {1} {2} {3}" -f $location.DisplayName, $publisher.PublisherName, $offer.Offer, $sku.Skus
$version = Get-AzVMImage -Location $location.DisplayName -PublisherName $publisher.PublisherName -Offer $offer.Offer -Skus $sku.Skus | Out-GridView -Title $titleVersions -PassThru
$imageReference = @{ publisher = $publisher.PublisherName; offer = $offer.Offer; sku = $sku.Skus; version = $version.Version }
$imageReference | ConvertTo-Json -Depth 4
Write-Warning "Use latest in the version field to get the latest version of the image"