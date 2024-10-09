param config object = loadJsonContent('../configs/aca.jsonc')
param env string
param containerName string
param imageBuild string = ''
param location string = resourceGroup().location

@description('Suffix to append to deployment names, defaults to MMddHHmmss')
param timeStamp string = utcNow('MMddHHmmss')

// Deploy the containerApp
var containerAppDeploymentObject = config[env].containerAppDeployment[containerName]

module containerApp 'br/public:avm/res/app/container-app:0.11.0' = {
  name: 'deploy-${containerAppDeploymentObject.name}-${timeStamp}'
  params: {
    // Required parameters
    name: containerAppDeploymentObject.name
    containers: [
      {
        // image: !empty(image) ? image : containerAppDeploymentObject.imageName
        image: imageBuild
        name: containerAppDeploymentObject.name
        env: containerAppDeploymentObject.?env ?? []
        volumeMounts: containerAppDeploymentObject.?volumeMounts ?? []
        probes: containerAppDeploymentObject.?probes ?? []
        resources: {
          cpu: json(containerAppDeploymentObject.containerCpuCoreCount)
          memory: containerAppDeploymentObject.containerMemory
        }
      }
    ]
    scaleMinReplicas: containerAppDeploymentObject.containerMinReplicas
    scaleMaxReplicas: containerAppDeploymentObject.containerMaxReplicas
    volumes: containerAppDeploymentObject.?volumes ?? []
    registries: [
      {
        server: '${containerAppDeploymentObject.acrName}.azurecr.io'
        identity: containerAppDeploymentObject.userAssignedIdentityId
      }
    ]
    environmentResourceId: containerAppDeploymentObject.managedEnvironmentId
    // Non-required parameters
    location: location
    disableIngress: containerAppDeploymentObject.?disableIngress ?? false
    ingressAllowInsecure: containerAppDeploymentObject.?ingressAllowInsecure ?? false
    ingressExternal: containerAppDeploymentObject.?external ?? false
    ingressTargetPort: containerAppDeploymentObject.targetPort
    ingressTransport: 'auto'
    corsPolicy: {
      allowedOrigins: union([ 'https://portal.azure.com', 'https://ms.portal.azure.com' ], containerAppDeploymentObject.allowedOrigins)
    }
    dapr: containerAppDeploymentObject.?dapr ?? { enabled: false }
    managedIdentities: {
      userAssignedResourceIds: [
        containerAppDeploymentObject.userAssignedIdentityId
      ]
    }
    secrets: {
      secureList: containerAppDeploymentObject.?secrets ?? []
    }
  }
}
