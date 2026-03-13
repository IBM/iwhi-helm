# IBM API Connect Helm Chart

Helm chart for deploying IBM API Connect 12.1.x on OpenShift Container Platform.  

Note: this version of the chart deploys at most one instance of each APIC subsystem in a single namespace (including the operators.)  Other deployment topologies are possible but are not (yet) covered by this chart.

## Prerequisites

### Ensure cert manager is deployed in the OpenShift cluster

### Apply the catalog sources

```bash
oc apply -f apiconnect-operator-release-files_12.1.0.1/catalog-sources/catalog-sources-common-services.yaml
oc apply -f apiconnect-operator-release-files_12.1.0.1/catalog-sources/catalog-sources-apiconnect.yaml
```

## Creation of the secrets

Note: you could possibly fetch these secrets in a vault and use an external secret operator.  

Ensure you've set the following two environment variables:
```bash
export NAMESPACE=<your-namespace>
export IBM_ENT_KEY=<your-entitlement-key>
```

Then create the following secrets:
```bash
# Create the pull secret containing the IBM Entitlement Key
oc create secret docker-registry ibm-entitlement-key \
  --docker-server=cp.icr.io \
  --docker-username=cp \
  --docker-password=$IBM_ENT_KEY \
  -n $NAMESPACE

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

## Helm configuration

Create environment-specific values file:

```bash
cp values.yaml examples/values-dev.yaml
# Edit values-dev.yaml with your configuration
```

Key parameters to configure:
- `global.namespace` - Target namespace
- `global.stackHost` - Ingress domain
- `global.license.accept` - Must be `true`
- `certificates.ingressIssuer.name` - Optional: use existing ClusterIssuer
- `certificates.internalIssuer.name` - Optional: use existing Issuer

## Deployment

The chart uses a `deployment.wave` parameter to control which components are deployed:
- wave 1: operators
- wave 2: certificates
- wave 3: subsystems (API manager, gateways, portals, analytics, ...)

### Wave 1 - Deploy Operators

```bash
helm upgrade --install apic-operators . \
  -f examples/values-dev.yaml \
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
  -f examples/values-dev.yaml \
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
  -f examples/values-dev.yaml \
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