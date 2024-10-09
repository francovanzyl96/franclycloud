targetScope = 'resourceGroup'

@description('Suffix to append to deployment names, defaults to MMddHHmmss')
param timeStamp string = utcNow('MMddHHmmss')

param location string = resourceGroup().location

param env string = 'dev'

param config object = loadJsonContent('../configs/cae.jsonc')

var KeyVaultSecretsUser = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
var acrPullRole = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')

var loggingObject = config[env].logging

module workspace 'br/public:avm/res/operational-insights/workspace:0.7.0' = {
  name: 'deploy-${loggingObject.logAnalytics.name}-${timeStamp}'
  params: {
    // Required parameters
    name: loggingObject.logAnalytics.name
    // Non-required parameters
    dailyQuotaGb: loggingObject.logAnalytics.dailyQuotaGb
    location: location
    managedIdentities: {
      systemAssigned: true
    }
    publicNetworkAccessForIngestion: 'Disabled'
    publicNetworkAccessForQuery: 'Disabled'
    tags: config.tags
    useResourcePermissions: true
  }
}

module component 'br/public:avm/res/insights/component:0.4.1' = {
  name: 'deploy-${loggingObject.ApplicationInsights.name}-${timeStamp}'
  params: {
    // Required parameters
    name: loggingObject.ApplicationInsights.name
    workspaceResourceId: workspace.outputs.resourceId
    // Non-required parameters
    retentionInDays: loggingObject.ApplicationInsights.retentionInDays
    location: config.location
    tags: config.tags
  }
}

var keyVaultObject = config[env].keyVault

module vault 'br/public:avm/res/key-vault/vault:0.9.0' = {
  scope: resourceGroup(keyVaultObject.resourceGroupName)
  name: 'deploy-keyvault-${timeStamp}'
  params: {
    // Required parameters
    name: keyVaultObject.name
    // Non-required parameters
    enablePurgeProtection: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enableRbacAuthorization: true
    publicNetworkAccess: 'Disabled'
    location: config.location
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
    }
    privateEndpoints: [
      {
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: keyVaultObject.privateDnsZoneResourceId
            }
          ]
        }
        service: 'vault'
        subnetResourceId: keyVaultObject.subnetResourceId
      }
    ]
    roleAssignments: [
      {
        principalId: containerAppServiceIdentity.outputs.principalId
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: KeyVaultSecretsUser
      }
    ]
  }
}

var managedEnvironmentObject = config[env].managedEnvironment

module managedEnvironment 'br/public:avm/res/app/managed-environment:0.8.0' = {
  name: 'deploy-${managedEnvironmentObject.name}-${timeStamp}'
  params: {
    // Required parameters
    logAnalyticsWorkspaceResourceId: workspace.outputs.resourceId
    name: managedEnvironmentObject.name
    // Non-required parameters
    infrastructureResourceGroupName: '${resourceGroup().name}-ace-infra'
    infrastructureSubnetId: resourceId(managedEnvironmentObject.vnetResourceGroup, 'Microsoft.Network/virtualNetworks/subnets', managedEnvironmentObject.vnetName, managedEnvironmentObject.subnetName)
    internal: true
    location: config.location
    tags: config.tags
    workloadProfiles: managedEnvironmentObject.workloadProfiles
  }
}

var privateDnsZoneObject = config[env].privateDnsZone
module privateDnsZone 'br/public:avm/res/network/private-dns-zone:0.6.0' = {
  name: 'deploy-privateDnsZone-${timeStamp}'
  scope: resourceGroup(privateDnsZoneObject.SubscriptionId, privateDnsZoneObject.resourceGroupName)
  params: {
    name: managedEnvironment.outputs.defaultDomain
    a: [
      {
        aRecords: [
          {
            ipv4Address: managedEnvironment.outputs.staticIp
          }
        ]
        name: 'A_${managedEnvironment.outputs.staticIp}'
        ttl: 3600
      }
    ]
    virtualNetworkLinks: [
      {
        registrationEnabled: false
        virtualNetworkResourceId: resourceId(privateDnsZoneObject.linkedVnets[0].subscriptionId, privateDnsZoneObject.linkedVnets[0].resourceGroupName, 'Microsoft.Network/virtualNetworks', privateDnsZoneObject.linkedVnets[0].vnetName)
      }
    ]
    tags: config.tags
  }
}

module containerAppServiceIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.0' = {
  name: 'deploy-${managedEnvironmentObject.name}-identity'
  params: {
    name: 'uami-${managedEnvironmentObject.name}'
    location: config.location
    tags: config.tags
  }
}

var containerRegistryObject = config[env].containerRegistry

module acr 'br/public:avm/res/container-registry/registry:0.5.1' = {
  scope: resourceGroup(containerRegistryObject.resourceGroupName)
  name: 'deploy-${containerRegistryObject.name}-${timeStamp}'
  params: {
    // Required parameters
    name: containerRegistryObject.name
    // Non-required parameters
    location: config.location
    acrAdminUserEnabled: false
    acrSku: containerRegistryObject.sku
    azureADAuthenticationAsArmPolicyStatus: 'enabled'
    exportPolicyStatus: 'enabled'
    privateEndpoints: [
      {
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: containerRegistryObject.privateDnsZoneResourceId
            }
          ]
        }
        subnetResourceId: containerRegistryObject.subnetResourceId
      }
    ]
    roleAssignments: [
      {
        principalId: containerAppServiceIdentity.outputs.principalId
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: acrPullRole
      }
    ]
    quarantinePolicyStatus: containerRegistryObject.quarantinePolicyStatus
    replications: []
    softDeletePolicyDays: 7
    softDeletePolicyStatus: 'disabled'
    trustPolicyStatus: 'enabled'
  }
}
