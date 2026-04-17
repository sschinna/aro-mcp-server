// ARO Cluster Bicep Template — Platform Workload Identity (Managed Identity)
// Microsoft.RedHatOpenShift/openShiftClusters@2024-08-12-preview
//
// This template uses Platform Workload Identity (no service principal needed).
// Each named identity maps to a specific ARO operator role. ARO creates and
// manages the federated credentials on these user-assigned managed identities.
//
// Prerequisites (run ONCE before deploying this template):
//   az feature register --namespace Microsoft.RedHatOpenShift --name PlatformWorkloadIdentityPreview
//   az provider register -n Microsoft.RedHatOpenShift

targetScope = 'resourceGroup'

// ── Parameters ───────────────────────────────────────────────────────────────

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Name of the ARO cluster.')
param clusterName string

@description('OpenShift Container Platform version.')
param clusterVersion string = '4.19.20'

@description('Domain prefix for the cluster (used in API/console URLs).')
param domain string = clusterName

@description('Resource group where ARO places cluster infrastructure (VMs, LBs). Must differ from this RG and must NOT already exist.')
param clusterResourceGroupId string

@description('Pull secret from https://console.redhat.com/openshift/install/pull-secret. Optional.')
@secure()
param pullSecret string = ''

@description('Master node VM size.')
param masterVmSize string = 'Standard_D8s_v3'

@description('Worker node VM size.')
param workerVmSize string = 'Standard_D4s_v3'

@description('Number of worker nodes (minimum 2).')
@minValue(2)
param workerCount int = 3

@description('Worker node OS disk size in GB (minimum 128).')
@minValue(128)
param workerDiskSizeGB int = 128

@description('API server visibility.')
@allowed(['Public', 'Private'])
param apiServerVisibility string = 'Public'

@description('Ingress visibility.')
@allowed(['Public', 'Private'])
param ingressVisibility string = 'Public'

@description('Pod CIDR. Must not overlap with VNet address space.')
param podCidr string = '10.128.0.0/14'

@description('Service CIDR. Must not overlap with VNet address space.')
param serviceCidr string = '172.30.0.0/16'

@description('Tags to apply to all resources.')
param tags object = {
  environment: 'demo'
  managedBy: 'bicep'
  aroVersion: '4.19'
}

@description('Deployment mode: bootstrap creates identities/network/RBAC only, cluster creates cluster only, all does both in one run.')
@allowed([
  'bootstrap'
  'cluster'
  'all'
])
param deploymentMode string = 'bootstrap'

var deployBootstrap = contains([
  'bootstrap'
  'all'
], deploymentMode)
var deployCluster = contains([
  'cluster'
  'all'
], deploymentMode)

// ── User-Assigned Managed Identities (Platform Workload Identity) ─────────────
// ARO with workload identity requires one UAI per operator role.

// Identity names must match exactly what ARO expects as keys in platformWorkloadIdentities.
// Use 'aro-cluster-identity' (index 0) as the cluster-level UAI; the rest map 1:1 to ARO operator roles.
var identityNames = [
  'aro-cluster-identity'      // [0] cluster-level identity (attached to cluster resource)
  'aro-operator'              // [1] aro-operator
  'cloud-controller-manager'  // [2] cloud-controller-manager
  'cloud-network-config'      // [3] cloud-network-config
  'disk-csi-driver'           // [4] disk-csi-driver
  'file-csi-driver'           // [5] file-csi-driver
  'image-registry'            // [6] image-registry
  'ingress'                   // [7] ingress
  'machine-api'               // [8] machine-api
]

var platformIdentityResourceIds = [
  for name in identityNames: resourceId('Microsoft.ManagedIdentity/userAssignedIdentities', '${clusterName}-${name}')
]

resource platformIdentities 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = [
  for name in identityNames: if (deployBootstrap) {
    name: '${clusterName}-${name}'
    location: location
    tags: tags
  }
]

var clusterIdentityResourceId = resourceId('Microsoft.ManagedIdentity/userAssignedIdentities', '${clusterName}-aro-cluster-identity')
var aroOperatorIdentityResourceId = resourceId('Microsoft.ManagedIdentity/userAssignedIdentities', '${clusterName}-aro-operator')
var ccmIdentityResourceId = resourceId('Microsoft.ManagedIdentity/userAssignedIdentities', '${clusterName}-cloud-controller-manager')
var cncIdentityResourceId = resourceId('Microsoft.ManagedIdentity/userAssignedIdentities', '${clusterName}-cloud-network-config')
var diskCsiIdentityResourceId = resourceId('Microsoft.ManagedIdentity/userAssignedIdentities', '${clusterName}-disk-csi-driver')
var fileCsiIdentityResourceId = resourceId('Microsoft.ManagedIdentity/userAssignedIdentities', '${clusterName}-file-csi-driver')
var imageRegistryIdentityResourceId = resourceId('Microsoft.ManagedIdentity/userAssignedIdentities', '${clusterName}-image-registry')
var ingressIdentityResourceId = resourceId('Microsoft.ManagedIdentity/userAssignedIdentities', '${clusterName}-ingress')
var machineApiIdentityResourceId = resourceId('Microsoft.ManagedIdentity/userAssignedIdentities', '${clusterName}-machine-api')

// ── Virtual Network ───────────────────────────────────────────────────────────

resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = if (deployBootstrap) {
  name: '${clusterName}-vnet'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: ['10.0.0.0/8']
    }
  }
}

resource masterSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = if (deployBootstrap) {
  parent: vnet
  name: 'master-subnet'
  properties: {
    addressPrefix: '10.0.0.0/23'
    serviceEndpoints: [
      { service: 'Microsoft.ContainerRegistry' }
    ]
    // Required by ARO: disable private link policies on master subnet
    privateLinkServiceNetworkPolicies: 'Disabled'
  }
}

resource workerSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = if (deployBootstrap) {
  parent: vnet
  name: 'worker-subnet'
  dependsOn: [masterSubnet]
  properties: {
    addressPrefix: '10.0.2.0/23'
    serviceEndpoints: [
      { service: 'Microsoft.ContainerRegistry' }
    ]
  }
}


// ── Role Assignments ──────────────────────────────────────────────────────────
// ARO validates that each platform workload identity has the required Azure roles
// BEFORE it proceeds with cluster provisioning. Without these assignments the RP
// returns InvalidPlatformWorkloadIdentity for the operator that is missing roles.
//
// Two sets of grants are required per operator UAI:
//   1. The UAI's own Azure RBAC role (so it can do its job)
//   2. Managed Identity Operator for the ARO RP SP (so ARO can federate the identity)
//   3. Managed Identity Operator for the cluster identity (so the cluster can use operators)

var networkContributorRoleId  = '4d97b98b-1d4f-4787-a291-c67834d212e7'
var contributorRoleId         = 'b24988ac-6180-42a0-ab88-20f7382dd24c'
var storageBlobDataContribId  = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
var managedIdentityOperatorId = 'f1a07417-d97a-45cb-824c-7a7467783830'

// ARO RP first-party service principal — object ID is tenant-specific
// App ID f1dd0a37-89c6-4e07-bcd1-ffd3d43d8875 → object ID below
var aroRpSpObjectId = '1679a87a-3db8-4d2a-af43-79d10ff9006c'

// ── Cluster identity: Network Contributor on VNet ─────────────────────────────
resource clusterIdentityVnetRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployBootstrap) {
  name: guid(vnet.id, platformIdentityResourceIds[0], networkContributorRoleId)
  scope: vnet
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', networkContributorRoleId)
    principalId: platformIdentities[0]!.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ── ARO RP: Managed Identity Operator on ALL UAIs (indices 1-8) ───────────────
// ARO RP must be able to read and federate each operator identity.
resource aroRpMioRoles 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for i in range(1, 8): if (deployBootstrap) {
    name: guid(platformIdentityResourceIds[i], aroRpSpObjectId, managedIdentityOperatorId)
    scope: platformIdentities[i]!
    properties: {
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', managedIdentityOperatorId)
      principalId: aroRpSpObjectId
      principalType: 'ServicePrincipal'
    }
  }
]

// ── Reliability hardening: RG-scope MIO grants ───────────────────────────────
// In some subscriptions, ARM can report role assignment success while effective
// permissions are still propagating per-identity. Adding RG-scope MIO reduces
// repeated ARO validation failures (InvalidClusterMSIPermissions) during create.
resource clusterIdentityRgMioRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployBootstrap) {
  name: guid(resourceGroup().id, platformIdentityResourceIds[0], managedIdentityOperatorId)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', managedIdentityOperatorId)
    principalId: platformIdentities[0]!.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource aroRpRgMioRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployBootstrap) {
  name: guid(resourceGroup().id, aroRpSpObjectId, managedIdentityOperatorId)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', managedIdentityOperatorId)
    principalId: aroRpSpObjectId
    principalType: 'ServicePrincipal'
  }
}

// ── Cluster identity: Managed Identity Operator on ALL operator UAIs ──────────
// The cluster identity must be able to assume each operator identity.
resource clusterIdentityMioRoles 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for i in range(1, 8): if (deployBootstrap) {
    name: guid(platformIdentityResourceIds[i], platformIdentityResourceIds[0], managedIdentityOperatorId)
    scope: platformIdentities[i]!
    properties: {
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', managedIdentityOperatorId)
      principalId: platformIdentities[0]!.properties.principalId
      principalType: 'ServicePrincipal'
    }
  }
]

// ── Operator-specific Azure RBAC roles ───────────────────────────────────────

// [1] aro-operator — Contributor on resource group
resource aroOperatorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployBootstrap) {
  name: guid(resourceGroup().id, platformIdentityResourceIds[1], contributorRoleId)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', contributorRoleId)
    principalId: platformIdentities[1]!.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// [2] cloud-controller-manager — Contributor on resource group (manages LBs, public IPs)
resource ccmRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployBootstrap) {
  name: guid(resourceGroup().id, platformIdentityResourceIds[2], contributorRoleId)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', contributorRoleId)
    principalId: platformIdentities[2]!.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// [3] cloud-network-config — Network Contributor on VNet
resource cloudNetworkConfigRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployBootstrap) {
  name: guid(vnet.id, platformIdentityResourceIds[3], networkContributorRoleId)
  scope: vnet
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', networkContributorRoleId)
    principalId: platformIdentities[3]!.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// [4] disk-csi-driver — Contributor on resource group (creates/attaches managed disks)
resource diskCsiRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployBootstrap) {
  name: guid(resourceGroup().id, platformIdentityResourceIds[4], contributorRoleId)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', contributorRoleId)
    principalId: platformIdentities[4]!.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// [5] file-csi-driver — Contributor on resource group (creates storage accounts + file shares)
resource fileCsiRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployBootstrap) {
  name: guid(resourceGroup().id, platformIdentityResourceIds[5], contributorRoleId)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', contributorRoleId)
    principalId: platformIdentities[5]!.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// [6] image-registry — Storage Blob Data Contributor (reads/writes registry blobs)
resource imageRegistryRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployBootstrap) {
  name: guid(resourceGroup().id, platformIdentityResourceIds[6], storageBlobDataContribId)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContribId)
    principalId: platformIdentities[6]!.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// [7] ingress — Network Contributor on VNet (manages ingress routes + load balancer)
resource ingressRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployBootstrap) {
  name: guid(vnet.id, platformIdentityResourceIds[7], networkContributorRoleId)
  scope: vnet
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', networkContributorRoleId)
    principalId: platformIdentities[7]!.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// [8] machine-api — Contributor on resource group (creates/deletes VMs for node scaling)
resource machineApiRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployBootstrap) {
  name: guid(resourceGroup().id, platformIdentityResourceIds[8], contributorRoleId)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', contributorRoleId)
    principalId: platformIdentities[8]!.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ── ARO Cluster ───────────────────────────────────────────────────────────────

resource aroCluster 'Microsoft.RedHatOpenShift/openShiftClusters@2024-08-12-preview' = if (deployCluster) {
  name: clusterName
  location: location
  tags: tags
  // Cluster-level user-assigned managed identity
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${clusterIdentityResourceId}': {}
    }
  }
  properties: {
    clusterProfile: {
      domain: domain
      version: clusterVersion
      resourceGroupId: clusterResourceGroupId
      pullSecret: pullSecret == '' ? null : pullSecret
      fipsValidatedModules: 'Disabled'
      // oidcIssuer is managed/set by ARO for workload identity clusters; omit here
    }
    networkProfile: {
      podCidr: podCidr
      serviceCidr: serviceCidr
      outboundType: 'Loadbalancer'
    }
    // No servicePrincipalProfile — using platformWorkloadIdentityProfile instead
    platformWorkloadIdentityProfile: {
      platformWorkloadIdentities: {
        'aro-operator':             { resourceId: aroOperatorIdentityResourceId }
        'cloud-controller-manager': { resourceId: ccmIdentityResourceId }
        'cloud-network-config':     { resourceId: cncIdentityResourceId }
        'disk-csi-driver':          { resourceId: diskCsiIdentityResourceId }
        'file-csi-driver':          { resourceId: fileCsiIdentityResourceId }
        'image-registry':           { resourceId: imageRegistryIdentityResourceId }
        ingress:                    { resourceId: ingressIdentityResourceId }
        'machine-api':              { resourceId: machineApiIdentityResourceId }
      }
    }
    masterProfile: {
      vmSize: masterVmSize
      subnetId: resourceId('Microsoft.Network/virtualNetworks/subnets', '${clusterName}-vnet', 'master-subnet')
      encryptionAtHost: 'Disabled'
    }
    workerProfiles: [
      {
        name: 'worker'
        vmSize: workerVmSize
        diskSizeGB: workerDiskSizeGB
        subnetId: resourceId('Microsoft.Network/virtualNetworks/subnets', '${clusterName}-vnet', 'worker-subnet')
        count: workerCount
        encryptionAtHost: 'Disabled'
      }
    ]
    apiserverProfile: {
      visibility: apiServerVisibility
    }
    ingressProfiles: [
      {
        name: 'default'
        visibility: ingressVisibility
      }
    ]
  }
  dependsOn: [
    clusterIdentityVnetRole
    aroRpMioRoles
    clusterIdentityMioRoles
    clusterIdentityRgMioRole
    aroRpRgMioRole
    aroOperatorRole
    ccmRole
    cloudNetworkConfigRole
    diskCsiRole
    fileCsiRole
    imageRegistryRole
    ingressRole
    machineApiRole
  ]
}

// ── Outputs ───────────────────────────────────────────────────────────────────

@description('ARO cluster resource ID.')
output clusterId string = deployCluster ? aroCluster.id : ''

@description('ARO console URL.')
output consoleUrl string = deployCluster ? aroCluster!.properties.consoleProfile.url : ''

@description('ARO API server URL.')
output apiServerUrl string = deployCluster ? aroCluster!.properties.apiserverProfile.url : ''

@description('Cluster identity resource ID.')
output clusterIdentityId string = clusterIdentityResourceId
