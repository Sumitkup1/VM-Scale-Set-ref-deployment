# VM Scale Set deployment Script

Script will deploy VMSS using Custom Image. VMSS scale set will be created in the private vNet with Azure Internal load balancer.

Script will capture image from VM instance deployed in Azure, will create image gallery, definition and customer VM image.

Script will create Azure ILB in the specified subnet and VMSS sets using custom image captured from VM instance.