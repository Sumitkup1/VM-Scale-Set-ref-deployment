# 02 Feb 2021 - Sumit Kumar

# Deploy Azure Scale set in your private vNet using marketplace windows image (with domain joined)
# VMSS instances will be joined to your AD domain

# Define variables for VMSS

$rgName = "smc_lhd_migrate01"
$location = "australiaeast"
$lbname = "VMSSLB001"

# Define variables for vmss configuration 

$scaleSetName = "vmsstest02"
$vmsize = "Standard_F1"
$AdminUsername = "vmssAdmin01";
$AdminPassword = "p4ssw0rd@123"; # Use complex password
$PublisherName = "MicrosoftWindowsServer"
$Offer         = "WindowsServer"
$Sku           = "2016-Datacenter-with-Containers"
$Version       = "latest"

# Settings to join scale sets to your AD Domain

$vmss_Settings = @{
        "Name" = "skforest01.com"; #specify domain name
        "User" = "skforest01\testvm01"; #User account with rights to domain join VMSS
        "Restart" = "true";
        "Options" = 3;
        "OUPath" = "OU=VMSS,DC=skforest01,DC=com" #OU location
    }

    $password = 'Welcome@123456' # Use complex password
    $ProtectedSettings =  @{
            "Password" = $password
    }


# Existing vNet details

$vnetname = "VNET01"
$vnetrsg = "aehubrsg01"

$vnet = Get-AzVirtualNetwork -Name $vnetname

$fe = 'auevmssfe01'
$ip = '10.0.1.10' ## change ip address based on your subnet range


# Identify subnet id in your vNet and change subnet in below command

$feip = New-AzLoadBalancerFrontendIpConfig -Name $fe -PrivateIpAddress $ip -SubnetId $vnet.subnets[0].Id 
$backendPool = New-AzLoadBalancerBackendAddressPoolConfig -Name "VMSSBEPool01"

# Custom port range for RDP connection

$inboundNATPool = New-AzLoadBalancerInboundNatPoolConfig `
  -Name "RDPRule" `
  -FrontendIpConfigurationId $feip.Id `
  -Protocol TCP `
  -FrontendPortRangeStart 50001 `
  -FrontendPortRangeEnd 50010 `
  -BackendPort 338

$lb = New-AzLoadBalancer `
-ResourceGroupName $rgName `
-Name $lbname `
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
  -SubnetId $vnet.Subnets[0].Id

# Create VMSS configuration

$VMSS = New-AzVmssConfig -Location $location -SkuCapacity 2 -SkuName $vmsize -UpgradePolicyMode "Automatic" `
   | Add-AzVmssNetworkInterfaceConfiguration -Name "Ipconfig" -Primary $True -IPConfiguration $ipConfig `
    | Set-AzVmssOSProfile -ComputerNamePrefix "aue" -AdminUsername $AdminUsername -AdminPassword $AdminPassword `
    | Set-AzVmssStorageProfile -OsDiskCreateOption 'FromImage' -OsDiskCaching "None" `
    -ImageReferenceOffer $Offer -ImageReferenceSku $Sku -ImageReferenceVersion $Version `
    -ImageReferencePublisher $PublisherName `
    | Add-AzureRmVmssExtension -Publisher "Microsoft.Compute" -Type "JsonADDomainExtension" -TypeHandlerVersion 1.3 -Name "vmssjoindomain" -Setting $vmss_Settings -ProtectedSetting $ProtectedSettings -AutoUpgradeMinorVersion $true


# Create VMSS
New-AzVmss -ResourceGroupName $RGName -Name $scaleSetName -VirtualMachineScaleSet $VMSS
