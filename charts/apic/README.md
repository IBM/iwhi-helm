# IBM API Connect Helm Chart

Helm chart for deploying IBM API Connect 12.1.x on OpenShift Container Platform.  

Note: this version of the chart deploys at most one instance of each APIC subsystem in a single namespace (including the operators.)  Other deployment topologies are possible but are not (yet) covered by this chart.

## Prerequisites

Ensure you've set the following environment variable, which is used in what follows:
```bash
export NAMESPACE=<your-namespace>
```

### Ensure cert manager is deployed in the OpenShift cluster

### Apply the catalog sources

```bash
oc apply -f apiconnect-operator-release-files_12.1.0.1/catalog-sources/catalog-sources-common-services.yaml
oc apply -f apiconnect-operator-release-files_12.1.0.1/catalog-sources/catalog-sources-apiconnect.yaml
```

### Creation of the pull secret

If you can directly pull the images from the official cp.icr.io IBM registry, then what you need here is an IBM entitlement key (the username being "cp"):
```bash
export DOCKER_SERVER=cp.icr.io
export DOCKER_USERNAME=cp
export DOCKER_PASSWORD=<your-entitlement-key>
```  

If you're mirroring the images in a local registry, you need to create a pull secret to access this registry:
```bash
export DOCKER_SERVER=<your-registry>
export DOCKER_USERNAME=<username-for-this-registry>
export DOCKER_PASSWORD=<password-for-this-registry>
```  

The following command creates the pull secret:
```bash
oc create secret docker-registry ibm-entitlement-key \
  --docker-server=$DOCKER_SERVER$ \
  --docker-username=$DOCKER_USERNAME \
  --docker-password=$DOCKER_PASSWORD \
  -n $NAMESPACE
```  

Note: we're calling this secret ibm-entitlement-key for convenience here, but you can name it whatever you want, as long as you specify the correct name in the Helm chart values file.  

### Creation of the subsystems secrets

Note: you could possibly fetch these secrets in a vault and use an external secret operator.  

```bash
# Create an encryption key for the devportal
oc create secret generic devportal-enc-key \
  --from-literal=encryption_secret=$(openssl rand -base64 16) -n $NAMESPACE

# Create an encryption key for the webMethods API Gateway
oc create secret generic wmapigateway-enc-key \
  --from-literal=password=$(openssl rand -base64 16) -n $NAMESPACE

# Create password for the Cloud Manager admin user
oc create secret generic management-admin-secret \
  --from-literal=password=$(openssl rand -base64 16) -n $NAMESPACE
```

### Helm configuration

In what follows, we use an environment variable containing the location of the custom values file:
```bash
export VALUES_FILE=<location-of-values-file>
```

Create environment-specific values file:

```bash
cp values.yaml $VALUES_FILE
```

Key parameters to configure:

**Global parameters:**
- `global.namespace` - Target namespace
- `global.appProductVersion` - the product version you want to install (or upgrade to) 
- `global.stackHost` - Ingress / Route domain
- `global.imageRegistry` - if you're pulling the images from a local registry, specify it here
- `global.imagePullSecret` - by default it points to a pull secret named ibm-entitlement-key, but you can change it
- `global.storageClass` - specify the storage class to be used for persistence

**Licence parameters:**  
See [documentation](https://www.ibm.com/docs/en/api-connect/software/12.1.0?topic=settings-basic-configuration) for more details regarding licenses.
- `global.license.accept` - you must set it to `true`, to mark your formal agreement
- `global.license.id` - specify a license ID from the version of API Connect that you are installing or are upgrading to
- `global.license.use` - production or nonproduction
- `global.license.metric` - PROCESSOR_VALUE_UNIT or MONTHLY_API_CALL

**Certificate parameters:**
Note: at this stage, only local issuers work with this Helm chart.
- `certificates.issuer.name` - if you want to use your own cert manager issuer, specify its name here (if omitted, a self signed issuer will be used)
- `certificates.issuer.kind` - kind of issuer (Issuer or ClusterIssuer)
- `certificates.issuer.caSecretName` - name of the secret containing your custom CA

**Management subsystem parameters:**
- `management.enabled` - set to `false` to skip this subsystem
- `management.profile` - sizing profile, see [documentation](https://www.ibm.com/docs/en/api-connect/software/12.1.0?topic=profiles-api-connect-deployment-openshift)
- `management.storageClass` - storage class for the database PVC; inherits `global.storageClass` if empty

Exposed routes (all under `global.stackHost`):
- `admin.<stackHost>` - Cloud Manager UI
- `manager.<stackHost>` - API Manager UI
- `api.<stackHost>` - Platform API
- `consumer.<stackHost>` - Consumer API
- `consumer-catalog.<stackHost>` - Consumer Catalog API

**Analytics subsystem parameters:**
- `analytics.enabled` - set to `false` to skip this subsystem
- `analytics.profile` - sizing profile, see [documentation](https://www.ibm.com/docs/en/api-connect/software/12.1.0?topic=profiles-api-connect-deployment-openshift)
- `analytics.storageClass` - storage class for data PVC; inherits `global.storageClass` if empty
- `analytics.storageType` - storage type (`shared` or `local`)
- `analytics.dataVolumeSize` - size of the data persistent volume (e.g. `100Gi`)
- `analytics.federatedAPIManagementMode` - set to `true` to enable analytics for the Federated API Management subsystem
- `analytics.devPortalMode` - set to `true` to enable analytics for the Developer Portal subsystem

Exposed routes:
- `ai.<stackHost>` - Analytics ingestion endpoint

**Developer Portal subsystem parameters:**
- `devportal.enabled` - set to `false` to skip this subsystem
- `devportal.profile` - sizing profile, see [documentation](https://www.ibm.com/docs/en/api-connect/software/12.1.0?topic=profiles-api-connect-deployment-openshift)
- `devportal.analyticsRef.name` - name of the AnalyticsCluster CR to link to
- `devportal.analyticsRef.namespace` - namespace of the analytics CR; inherits `global.namespace` if empty

Exposed routes:
- `api.devportal.<stackHost>` - Developer Portal admin API
- `devportal.<stackHost>` - Developer Portal web UI

**webMethods API Gateway subsystem parameters:**
- `wmapigateway.enabled` - set to `false` to skip this subsystem
- `wmapigateway.profile` - sizing profile, see [documentation](https://www.ibm.com/docs/en/api-connect/software/12.1.0?topic=profiles-api-connect-deployment-openshift)
- `wmapigateway.imageRegistry` - override image registry; inherits `global.imageRegistry` if empty
- `wmapigateway.storageClass` - storage class for data PVC; inherits `global.storageClass` if empty
- `wmapigateway.dataVolumeSize` - size of the data persistent volume (e.g. `10Gi`)
- `wmapigateway.encryptionSecret.enabled` - set to `true` to configure an encryption secret
- `wmapigateway.encryptionSecret.secretName` - name of the Kubernetes secret containing the encryption password (key: `password`)

Exposed routes:
- `wmapigateway-gw.<stackHost>` - Gateway endpoint
- `wmapigateway-ui.<stackHost>` - webMethods API Gateway UI
- `wmapigateway-mgmt.<stackHost>` - Management endpoint

**Nano Gateway subsystem parameters:**
- `nanogateway.enabled` - set to `false` to skip this subsystem
- `nanogateway.profile` - sizing profile, see [documentation](https://www.ibm.com/docs/en/api-connect/software/12.1.0?topic=licensing-datapower-nano-gateway-deployment-profile-limits)
- `nanogateway.imageRegistry` - image registry for DataPower images (e.g. `cp.icr.io/cp/datapower`); inherits `global.imageRegistry` if empty
- `nanogateway.redis.host` - **REQUIRED** – Redis/Valkey host FQDN or IP
- `nanogateway.redis.port` - Redis port (default: `6379`)
- `nanogateway.redis.mode` - Redis topology (`standalone` or `sentinel`)
- `nanogateway.redis.credentialSecret` - name of the secret containing Redis credentials
- `nanogateway.redis.tlsSecret` - name of the secret containing the Redis TLS certificate

Exposed routes:
- `apic-gateway-proxy.<stackHost>` - Management endpoint
- `nanogw.<stackHost>` - Gateway domain (used as wildcard base for API routes)

**Federated API Management subsystem parameters:**
- `federatedapimanagement.enabled` - set to `false` to skip this subsystem
- `federatedapimanagement.profile` - sizing profile, see [documentation](https://www.ibm.com/docs/en/api-connect/software/12.1.0?topic=profiles-api-connect-deployment-openshift)
- `federatedapimanagement.analyticsRef.name` - name of the AnalyticsCluster CR to link to
- `federatedapimanagement.analyticsRef.namespace` - namespace of the analytics CR; inherits `global.namespace` if empty

Exposed routes:
- `fam.<stackHost>` - Federated API Management UI
- `api.fam.<stackHost>` - Admin API endpoint

**DataPower API Gateway subsystem parameters:**
- `apigw.enabled` - set to `false` to skip this subsystem (disabled by default)
- `apigw.profile` - sizing profile, see [documentation](https://www.ibm.com/docs/en/api-connect/software/12.1.0?topic=profiles-api-connect-deployment-openshift)
- `apigw.platformCASecret` - name of the secret containing the platform CA used for mTLS
- `apigw.adminUserSecret` - name of the secret containing the DataPower admin credentials


## Deployment

The chart uses a `deployment.wave` parameter to control which components are deployed:
- wave 1: operators
- wave 2: certificates
- wave 3: subsystems (API manager, gateways, portals, analytics, ...)

When using ArgoCD with this chart, you can set `deployment.wave` to the value "all", and configure ArgoCD to orchestrate the installation using the argocd.argoproj.io/sync-wave annotation that's in the Helm templates.  

### Wave 1 - Deploy Operators

```bash
helm upgrade --install apic-operators . \
  -f $VALUES_FILE \
  --set deployment.wave=1 \
  -n $NAMESPACE
```

**Wait for operators to be ready (2-5 minutes):**

```bash
# Check ClusterServiceVersions (ibm-apiconnect, ibm-common-service-operator, operand-deployment-lifecycle-manager must be in PHASE: Succeeded)
oc get csv -n $NAMESPACE -l operators.coreos.com/ibm-common-service-operator.iwhi
oc get csv -n $NAMESPACE -l operators.coreos.com/ibm-apiconnect.iwhi
oc get csv -n $NAMESPACE -l operators.coreos.com/ibm-odlm.iwhi

# Verify the operator pods are running (pods ibm-apiconnect-*, ibm-common-service-operator-* and operand-deployment-lifecycle-manager-* must be in status Running)
oc get pod -n $NAMESPACE -l app.kubernetes.io/component=apiconnect-operator
oc get pod -n $NAMESPACE -l app.kubernetes.io/instance=ibm-common-service-operator
oc get pod -n $NAMESPACE -l app.kubernetes.io/instance=operand-deployment-lifecycle-manager
```

### Wave 2 - Deploy Certificates

Note 1: this Helm chart currently does not work with cluster issuers.  
Note 2: if you're using a local issuer, make sure to have it created in the namespace before starting wave 2.

```bash
helm upgrade --install apic-certificates . \
  -f $VALUES_FILE \
  --set deployment.wave=2 \
  -n $NAMESPACE
```

**Wait for certificates to be ready (1-3 minutes):**

Check certificates (All certificates should show READY: True):
```bash 
oc get certificate -n $NAMESPACE
```

### Wave 3 - Deploy Subsystems

```bash
helm upgrade --install apic-subsystems . \
  -f $VALUES_FILE \
  --set deployment.wave=3 \
  -n $NAMESPACE
```

**Monitor subsystem deployment (~30 minutes):**

Check subsystem statuses (all subsystems must show Phase: Ready):
```bash
oc get managementcluster.management.apiconnect.ibm.com/management -n $NAMESPACE
oc get analyticscluster.analytics.apiconnect.ibm.com/analytics -n $NAMESPACE
oc get wmapigatewaycluster.wmapigateway.apiconnect.ibm.com/wmapigateway -n $NAMESPACE
oc get devportalcluster.devportal.apiconnect.ibm.com/devportal -n $NAMESPACE
oc get federatedapimanagementcluster.federatedapimanagement.apiconnect.ibm.com/fam -n $NAMESPACE
```

## Post installation

1. Configure the management subsystem (Connect to an email email, Create a provider organization)
2. Add Analytics subsystem to the Cloud Manager topology
3. (if applicable) Add webMethods API Gateway subsystem to the Cloud Manager topology
4. (if applicable) Add DataPower API Gateway subsystem to the Cloud Manager topology
5. (if applicable) Add DataPower Nanogateway subsystem to the Cloud Manager topology
6. (if applicable) Add webMethods Developer Portal subsystem to the Cloud Manager topology
7. (if applicable) Add CMS Developer Portal subsystem to the Cloud Manager topology

## Uninstallation

Remove in reverse order
```bash
helm uninstall apic-subsystems -n $NAMESPACE
helm uninstall apic-certificates -n $NAMESPACE
helm uninstall apic-operators -n $NAMESPACE
```
  
Clean up secrets if needed