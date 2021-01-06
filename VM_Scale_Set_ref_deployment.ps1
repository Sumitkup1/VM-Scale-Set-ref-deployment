# 04 Jan 2021 - Sumit Kumar

# Script custom image for virtual machine scale sets with Azure PowerShell

#Install-Module -Name Az -AllowClobber -Force
#$PSVersionTable.PSVersion
#Install-Module -Name PowerShellGet -Force


$vmname = "vmss-srv01"
$rsgname= "servicenowazmidservers-rgp-01"
$vmssgallery= "vmssmidservers"

################################################################################################
$sourceVM = Get-AzVM -Name $vmname -ResourceGroupName $rsgname
$rsg = Get-AzResourceGroup -Name $rsgname -Location 'australiaeast'


$gallery = New-AzGallery -GalleryName $vmssgallery -ResourceGroupName $rsg.ResourceGroupName -Location $rsg.Location -Description 'VMSS Image Gallery for MID ServiceNow'

$Image = New-AzGalleryImageDefinition -GalleryName $gallery.Name -ResourceGroupName $rsg.ResourceGroupName `
   -Location $gallery.Location `
   -Name 'MIDImageDef' `
   -OsState specialized `
   -OsType Windows `
   -Publisher 'eHealthPublisher' `
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

# Define variables for the scale set

$resourceGroupName = "servicenowazmidservers-rgp-01"
$scaleSetName = "MIDvmss001"
$location = "australiaeast"
$pipname = "eHealthpip01"

$vmssgallery= "vmssmidservers"

$galleryImage = Get-AzGalleryImageDefinition -ResourceGroupName $resourceGroupName -GalleryName $vmssgallery

$vnetname = "Provider-INF-VNET-01"
$vnetrsg = "Provider-INF-RGP-01"
$Subnetname = "ServiceNowAZMIDServers-SNET-01" # 10.134.1.128/27 (128 to 159)

$vnet = Get-AzVirtualNetwork -Name $vnetname

$vnet.Subnets[11]

## Variables for the commands ##
$fe = 'VMSSFE01'
$ip = '10.134.1.150' ##change this ip address

#change subnet id before running

$feip = New-AzLoadBalancerFrontendIpConfig -Name $fe -PrivateIpAddress $ip -SubnetId $vnet.subnets[11].Id 

<#
$publicIP = New-AzPublicIpAddress `
  -ResourceGroupName $rsgname `
  -Location $location `
  -AllocationMethod Static `
  -Name $pipname

  $frontendIP = New-AzLoadBalancerFrontendIpConfig `
  -Name "myFrontEndPool" `
  -PublicIpAddress $publicIP
  #>

$backendPool = New-AzLoadBalancerBackendAddressPoolConfig -Name "VMSSBEPool01"

#may not be needed
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
-Name "VMSSMIDLB001" `
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