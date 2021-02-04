# VM Scale Set Reference Script

## VM_Scale_Set_ref_arch01.ps1 

Script will deploy VMSS using Custom Image. VMSS scale set will be created in your private vNet with Azure Internal load balancer.

Script will capture image from VM instance deployed in Azure, will create image gallery, definition and custom VM image.

Script will create Azure ILB in the specified subnet and VMSS sets using custom image captured from VM instance.

## VM_Scale_Set_ref_arch02.ps1 

Script will deploy VMSS using Azure marketplace windows Image. VMSS scale set will be created in your private vNet with Azure Internal load balancer.

VMSS instances will be AD domain joined - Script has AD domain joined code to join instances to your AD domain/forest.