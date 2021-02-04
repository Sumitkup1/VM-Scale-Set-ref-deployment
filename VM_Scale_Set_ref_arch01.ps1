# 04 Jan 2021 - Sumit Kumar

# Deploy Azure Scale set in your private vNet using custom image (without domain joined)


# Define variables for VM scale set

$vmname = "vmss-srv01"
$rsgname= "auevmrgp01"
$vmssgallery= "auevmssgly01"

################################################################################################

# Capture Image from VM, create image gallery, image definition and version

$sourceVM = Get-AzVM -Name $vmname -ResourceGroupName $rsgname
$rsg = Get-AzResourceGroup -Name $rsgname -Location 'australiaeast'


$gallery = New-AzGallery -GalleryName $vmssgallery -ResourceGroupName $rsg.ResourceGroupName -Location $rsg.Location -Description 'VMSS Image Gallery'

$Image = New-AzGalleryImageDefinition -GalleryName $gallery.Name -ResourceGroupName $rsg.ResourceGroupName `
   -Location $gallery.Location `
   -Name 'VmssImageDef' `
   -OsState specialized `
   -OsType Windows ` # Change OsType to linux if source VM is Linux OS 
   -Publisher 'OrgPublisher' `
   -Offer 'myOffer' `
   -Sku 'mySKU'


$pri = @{Name='australiaeast';ReplicaCount=1}
$sec = @{Name='australiasoutheast';ReplicaCount=2}
$regions = @($pri,$sec)

New-AzGalleryImageVersion `
   -GalleryImageDefinitionName $Image.Name`
   -GalleryImageVersionName '1.0.0' `
   -GalleryName $gallery.Name `
   -ResourceGroupName $rsg.ResourceGroupName `
   -Location $rsg.Location `
   -TargetRegion $regions  `
   -Source $sourceVM.Id.ToString() `
   -PublishingProfileEndOfLifeDate '2021-12-01'

################################################################################################

## Below code is to deploy internal LB and VMSS using image gallery created in the previous section

# Define variables for the scale set

$resourceGroupName = "auevmssrgp02"
$scaleSetName = "auevmss001"
$location = "australiaeast"
$pipname = "auevmsspip01"

$vmssgallery= "auevmssgly01"

$galleryImage = Get-AzGalleryImageDefinition -ResourceGroupName $resourceGroupName -GalleryName $vmssgallery

$vnetname = "VNET01"
$vnetrsg = "aueinfrsg01"
$Subnetname = "snx001" 

$vnet = Get-AzVirtualNetwork -Name $vnetname

$vnet.Subnets[11]

$fe = 'auevmssfe01'
$ip = '10.134.1.150' ## change ip address based on your subnet range

# Identify subnet id in your vNet and change subnet in below command

$feip = New-AzLoadBalancerFrontendIpConfig -Name $fe -PrivateIpAddress $ip -SubnetId $vnet.subnets[11].Id 

$backendPool = New-AzLoadBalancerBackendAddressPoolConfig -Name "VMSSBEPool01"

# (Optional)
$inboundNATPool = New-AzLoadBalancerInboundNatPoolConfig `
  -Name "RDPRule" `
  -FrontendIpConfigurationId $feip.Id `
  -Protocol TCP `
  -FrontendPortRangeStart 50001 `
  -FrontendPortRangeEnd 50010 `
  -BackendPort 3389

# Create the load balancer and health probe

$lb = New-AzLoadBalancer `
-ResourceGroupName $resourceGroupName `
-Name "VMSSLB001" `
-Location $location `
-FrontendIpConfiguration $feip `
-BackendAddressPool $backendPool `
-InboundNatPool $inboundNATPool
Add-AzLoadBalancerProbeConfig -Name "HealthProbe" `
-LoadBalancer $lb `
-Protocol TCP `
-Port 80 `
-IntervalInSeconds 15 `
-ProbeCount 2
Add-AzLoadBalancerRuleConfig `
-Name "LoadBalancerRule" `
-LoadBalancer $lb `
-FrontendIpConfiguration $lb.FrontendIpConfigurations[0] `
-BackendAddressPool $lb.BackendAddressPools[0] `
-Protocol TCP `
-FrontendPort 80 `
-BackendPort 80 `
-Probe (Get-AzLoadBalancerProbeConfig -Name "HealthProbe" -LoadBalancer $lb)
Set-AzLoadBalancer -LoadBalancer $lb

# Create IP address configurations
$ipConfig = New-AzVmssIpConfig `
  -Name "IPConfig" `
  -LoadBalancerBackendAddressPoolsId $lb.BackendAddressPools[0].Id `
  -LoadBalancerInboundNatPoolsId $inboundNATPool.Id `
  -SubnetId $vnet.Subnets[11].Id

# Create a configuration 
$vmssConfig = New-AzVmssConfig `
    -Location $location `
    -SkuCapacity 2 `
    -SkuName "Standard_D2s_v3" `
    -UpgradePolicyMode "Automatic"

# Reference the image version
Set-AzVmssStorageProfile $vmssConfig `
  -OsDiskCreateOption "FromImage" `
  -ImageReferenceId $galleryImage.Id

# Complete the configuration
 
Add-AzVmssNetworkInterfaceConfiguration `
  -VirtualMachineScaleSet $vmssConfig `
  -Name "network-config" `
  -Primary $true `
  -IPConfiguration $ipConfig 

# Create the scale set 
New-AzVmss `
  -ResourceGroupName $resourceGroupName `
  -Name $scaleSetName `
  -VirtualMachineScaleSet $vmssConfig