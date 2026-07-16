# IBM API Connect Helm Chart

Helm chart for deploying IBM API Connect 12.1.x on OpenShift Container Platform.  

Notes:
- This version of the chart deploys at most one instance of each APIC subsystem in a single namespace (including the operators.)  Other deployment topologies are possible but are not (yet) covered by this chart.
- The DataPower API Gateway is not yet handled by this chart — only the webMethods API Gateway and the DataPower Nano Gateway are supported.
- The CMS-based Developer Portal (Drupal) is not yet handled — only the webMethods Developer Portal is supported.

## Infrastructure Requirements

### Compute (CPU / memory)

Each subsystem is sized independently via its own `<subsystem>.profile` value (see `values.yaml`), following IBM's own profile naming (e.g. `n1xc2.m16`). The actual CPU/memory reserved per profile is defined by IBM, not by this chart, and depends on the API Connect / Nano Gateway version — always check the official tables before sizing a cluster:
- API Connect subsystems (Management, Analytics, Developer Portal, webMethods API Gateway, Federated API Management): [Deployment profiles](https://www.ibm.com/docs/en/api-connect/software/12.1.0?topic=profiles-api-connect-deployment-openshift)
- Nano Gateway: [Deployment profile limits](https://www.ibm.com/docs/en/api-connect/software/12.1.0?topic=licensing-datapower-nano-gateway-deployment-profile-limits)

Default profiles configured in this chart's `values.yaml`:

| Subsystem | Value | Default |
|---|---|---|
| Management | `management.profile` | `n1xc2.m16` |
| Analytics | `analytics.profile` | `n1xc2.m16` |
| Developer Portal | `devportal.profile` | `n1xc2.m4` |
| webMethods API Gateway | `wmapigateway.profile` | `n1xc3.m6` |
| Nano Gateway (if enabled) | `nanogateway.profile` | `n1xc2.m4` |
| Federated API Management | `federatedapimanagement.profile` | `n1xc3.m4` |

On top of the subsystems above, budget CPU/memory for the operators themselves, deployed in wave 1: **~1.2 CPU / ~1.4Gi mem (requests) minimum, up to 5.5 CPU / 5.5Gi mem (limits)** — sum of `ibm-apiconnect`, the Nano Gateway operator and the Valkey operator (the only ones with resources fixed in this chart/repo). Common Services, ODLM and the EDB Postgres operator run alongside them but aren't shipped as manifests here.

### Storage

`global.storageClass` sets the default block storage class for all persistent volumes (default in `values.yaml`: `ocs-external-storagecluster-ceph-rbd` — OpenShift Data Foundation / Ceph RBD, `ReadWriteOnce`). Individual subsystems can override it via their own `<subsystem>.storageClass` (falls back to `global.storageClass` when left empty). See IBM's [Estimating storage requirements](https://www.ibm.com/docs/en/api-connect/software/12.1.1?topic=planning-estimating-storage-requirements) for sizing guidance per subsystem.

Explicit volume sizes configured by this chart:

| Subsystem | Value | Default |
|---|---|---|
| Analytics | `analytics.dataVolumeSize` | `100Gi` |
| webMethods API Gateway | `wmapigateway.dataVolumeSize` | `10Gi` |
| Valkey (if enabled) | `valkey.nodeConfStorageSize` | `1Gi` (node config volume, always created) |

Other subsystems (Management, Developer Portal, Federated API Management) provision their own PVCs internally, sized by their `profile` rather than by this chart — see the IBM profile tables above.

Valkey's actual data volumes are only created if `valkey.persistenceEnabled: true` (default `false`, i.e. in-memory only); size and count then depend on `valkey.clusterSize` / `leaderReplicas` / `followerReplicas`, not on a single chart value.

A block storage class supporting dynamic provisioning is required; this chart does not use `ReadWriteMany` volumes.

## Platform-level Prerequisites

Everything in this section is **cluster-scoped**: it requires cluster-admin-level RBAC, is done once per cluster (not once per installation), and is owned by the **platform team**. The feature team does not need any of these permissions for the rest of this README.

### Create the target namespace

This chart never creates the namespace itself — it's an external prerequisite:
```bash
export NAMESPACE=<your-namespace>
oc create namespace $NAMESPACE
```

### Ensure cert manager is deployed in the OpenShift cluster

Check whether the Red Hat cert-manager operator is already installed:
```bash
oc get csv -A | grep cert-manager
```

If it's not installed, deploy the Red Hat-supported operator (`openshift-cert-manager-operator`):
```bash
oc apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: cert-manager-operator
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: cert-manager-operator
  namespace: cert-manager-operator
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-cert-manager-operator
  namespace: cert-manager-operator
spec:
  channel: stable-v1
  name: openshift-cert-manager-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
```

Wait until the operator is ready:
```bash
oc get csv -n cert-manager-operator -w
```

### Apply the catalog sources

API Connect requires 3 catalog sources to be available in the cluster:
- `ibm-apiconnect`
- `ibm-cp-common-services`
- `ibm-cloud-native-postgresql`

These are published as CASE packages on [IBM/cloud-pak/repo/case](https://github.com/IBM/cloud-pak/tree/master/repo/case), where you can also find them for other product versions.

A copy of the catalog sources needed for this chart is included in this repo. Install them with:
```bash
oc apply -f catalog-sources/12.1.1.0/catalog-sources-apiconnect.yaml
```

**Air-gapped clusters**: the command above points the catalog sources at the public IBM registry, which won't be reachable. Mirror the CASE packages' images to your own registry first and apply the mirrored catalog sources instead — see `airgapped-install.md` at the repo root for the full procedure.

### Apply the cluster-scoped CRDs (only if the Nano Gateway subsystem will be installed)

Installs the Nano Gateway CRDs, and the Valkey CRDs (unless the feature team runs Valkey outside this chart) — cluster-scoped, outside Helm (`oc apply`, not `helm install`).

```bash
oc apply -f cluster/crds/nanogateway-crds.yaml
oc apply -f cluster/crds/valkey-crds.yaml   # skip if Valkey/Redis is run outside this chart
```

Safe to re-run (`oc apply` is idempotent). Unlike Helm's `crds/` convention, this is **not** a one-time-on-first-install step — re-run it whenever `cluster/crds/*.yaml` changes on a chart upgrade, since Helm never manages these files.

If the target cluster is older than OpenShift 4.19, the cluster-wide Gateway API CRDs are also required (not namespaced, not shipped by this chart):
```bash
oc apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml
```

Wave 1 checks that the Gateway API (`gateway.networking.k8s.io/v1`) is available in the target cluster before deploying the Nano Gateway operator, and fails with instructions if it is missing. This check requires a live cluster connection, so it always fails under `helm template` / `helm install --dry-run=client` / CI. Skip it explicitly in those contexts:
```bash
--set nanogateway.skipGatewayApiCheck=true
```

### Apply the cluster-scoped RBAC (only if the Nano Gateway subsystem will be installed)

Grants the Nano Gateway and Valkey operator ServiceAccounts (created later, namespace-scoped, in wave 1) the ClusterRole they need — outside Helm (`oc apply`, not `helm install`). The feature team never needs to run this, and its own namespace-scoped RBAC (see wave 1 below) does not grant these permissions.

```bash
envsubst '$NAMESPACE' < cluster/rbac/nanogateway-operator.yaml | oc apply -f -
envsubst '$NAMESPACE' < cluster/rbac/valkey-operator.yaml | oc apply -f -   # skip if Valkey/Redis is run outside this chart
```

Or, both CRDs and RBAC together, via the Makefile:
```bash
make wave0 NAMESPACE=$NAMESPACE
```

If you deploy multiple `datapower-nano-operator` instances across several namespaces (one per feature team), the `ClusterRoleBinding` in `cluster/rbac/nanogateway-operator.yaml` needs one subject per namespace — add them manually before re-applying; `envsubst` only substitutes a single `$NAMESPACE` and will overwrite, not merge, the existing subjects list.

### Allow wildcard routes (only if the Nano Gateway subsystem will be installed)

OpenShift rejects wildcard routes by default; the Nano Gateway's wildcard route (`nanogw.<stackHost>`, used as the base for all API routes) stays `Rejected` without this. One-time, cluster-admin-level change to the cluster's default `IngressController`:

```bash
oc patch ingresscontroller default -n openshift-ingress-operator --type=merge -p '{"spec":{"routeAdmission":{"wildcardPolicy":"WildcardsAllowed"}}}'
```

If this change isn't made (or isn't possible on a shared cluster), the Nano Gateway subsystem still works, but the feature team must instead create an explicit, namespace-scoped Route for every API or API product exposed through the Nano Gateway, one by one, rather than relying on the single wildcard route to cover all of them.

## Feature-team-level Prerequisites

Everything in this section is **namespace-scoped**, inside `$NAMESPACE` created by the platform team above. This is what the feature team runs, without needing any cluster-scoped permissions.

```bash
export NAMESPACE=<your-namespace>
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
  --docker-server=$DOCKER_SERVER \
  --docker-username=$DOCKER_USERNAME \
  --docker-password=$DOCKER_PASSWORD \
  -n $NAMESPACE
```  

Note: we're calling this secret ibm-entitlement-key for convenience here, but you can name it whatever you want, as long as you specify the correct name in the Helm chart values file.  

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
`certificates.issuer.*` controls a single issuer used for BOTH the internal mTLS leaf certificates exchanged between subsystems AND the public ingress endpoints of each subsystem CR (Cloud Manager, API Manager, ...). Using the same CA for both is required: if they're signed by different, unrelated CAs, cross-subsystem calls that go through a public endpoint (e.g. Management registering the Analytics service by calling its public `ai.<stackHost>` URL) fail with a TLS trust error.
- `certificates.issuer.mode` - `operator` (default) or `existing`
  - `operator`: no issuer annotation is set on any CR for the ingress endpoints — requires API Connect 12.1.1+, since the `ibm-apiconnect` operator then creates and manages its own namespace-scoped `apic-ingress-issuer` automatically once it reconciles at least one CR needing it (wave 3). This chart's internal mTLS leaf certificates (created in wave 2) reference that same `apic-ingress-issuer` as their issuer — a single CA is used everywhere, with no externally pre-created Issuer/ClusterIssuer needed. Since the issuer doesn't exist yet when the wave 2 certificates are created, they show as Pending ("Referenced Issuer not found") until wave 3 runs, then turn Ready automatically within seconds — this is expected and doesn't fail wave 2. This chart never creates a ClusterIssuer, matching a namespace-scoped operator deployment.
  - `existing`: reference a single Issuer or ClusterIssuer you already created (see `examples/custom-issuer.yaml` / `examples/custom-clusterissuer.yaml`), used both as the `issuerRef` for internal leaf certificates and, via the `apiconnect-operator/default-ingress-issuer` / `apiconnect-operator/default-ingress-cluster-issuer` CR annotation, for the ingress endpoints. This chart never creates the Issuer/ClusterIssuer itself — it must already exist and be Ready before wave 2.
- `certificates.issuer.kind` - `Issuer` or `ClusterIssuer` (only used when `mode: existing`)
- `certificates.issuer.name` - name of the existing Issuer/ClusterIssuer (required when `mode: existing`)

**Management subsystem parameters:**
- `management.enabled` - set to `false` to skip this subsystem
- `management.profile` - sizing profile, see [documentation](https://www.ibm.com/docs/en/api-connect/software/12.1.0?topic=profiles-api-connect-deployment-openshift)
- `management.storageClass` - storage class for the database PVC; inherits `global.storageClass` if empty
- `management.adminSecret.name` - name of the Cloud Manager admin password secret (default: `management-admin-secret`)
- `management.adminSecret.autoGenerate` - set to `false` to manage this secret yourself instead of having this chart generate it

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
- `wmapigateway.encryptionSecret.autoGenerate` - set to `false` to manage this secret yourself instead of having this chart generate it
- `wmapigateway.adminSecret.name` - name of the webMethods API Gateway Administrator password secret (default: `wmapigateway-admin-secret`); managed entirely by the `ibm-apiconnect` operator, not by this chart (see "Subsystem secrets" above)

Exposed routes:
- `wmapigateway-gw.<stackHost>` - Gateway endpoint
- `wmapigateway-ui.<stackHost>` - webMethods API Gateway UI
- `wmapigateway-mgmt.<stackHost>` - Management endpoint

**Nano Gateway subsystem parameters:**
- `nanogateway.enabled` - set to `true` to deploy this subsystem (disabled by default; also deploys its dedicated operator in wave 1, which requires Gateway API - see prerequisites above)
- `nanogateway.skipGatewayApiCheck` - set to `true` to bypass the Gateway API availability check in wave 1 (required for `helm template` / `--dry-run=client` / CI, which have no live cluster to check against)
- `nanogateway.profile` - sizing profile, see [documentation](https://www.ibm.com/docs/en/api-connect/software/12.1.0?topic=licensing-datapower-nano-gateway-deployment-profile-limits)
- `nanogateway.imageRegistry` - image registry for the Nano Gateway workload images (gateway-proxy, ingw, analytics-collector, system-check). Default: `cp.icr.io/cp/apic` (or your mirror's equivalent path)
- `nanogateway.operatorImage` - `datapower-nano-operator` image (digest-pinned)
- `nanogateway.operatorResources` - CPU/memory limits and requests for the operator
- `nanogateway.redis.host` - Redis/Valkey host FQDN or IP. Leave empty to automatically use the in-chart Valkey deployment (requires `valkey.enabled: true`)
- `nanogateway.redis.port` - Redis port (default: `6379`)
- `nanogateway.redis.mode` - Redis topology (`standalone`, `sentinel` or `cluster`)
- `nanogateway.redis.credentialSecret` - name of the secret containing Redis credentials
- `nanogateway.redis.tlsSecret` - name of the secret containing the Redis TLS certificate

Exposed routes:
- `apic-gateway-proxy.<stackHost>` - Management endpoint
- `nanogw.<stackHost>` - Gateway domain (used as wildcard base for API routes)

**Valkey key-value store parameters (required by Nano Gateway):**

Valkey is the Redis-compatible key-value store required by the Nano Gateway subsystem. Set `valkey.enabled: true` to have this chart deploy it for you (operator in wave 1, TLS certificates in wave 2, ValkeyCluster CR in wave 3), instead of standing up the store separately and pointing `nanogateway.redis.host` at it.

- `valkey.enabled` - set to `true` to deploy the Valkey operator and cluster alongside API Connect
- `valkey.operatorImage` - Valkey operator image (digest-pinned)
- `valkey.operatorResources` - CPU/memory limits and requests for the operator
- `valkey.image` - Valkey image (digest-pinned)
- `valkey.clusterSize` - number of leader shards (default: `3`)
- `valkey.leaderReplicas` - replicas per leader (default: `3`)
- `valkey.followerReplicas` - replicas per follower (default: `3`)
- `valkey.clusterVersion` - Valkey protocol version (default: `v7`)
- `valkey.persistenceEnabled` - enable persistent storage for data (default: `false`)
- `valkey.nodeConfStorageSize` - storage size for the node config volume (default: `1Gi`)
- `valkey.storageClass` - storage class for the node config PVC; inherits `global.storageClass` if empty
- `valkey.credentialSecret.name` - name of the secret holding the Valkey password (default: `valkey-secret`)
- `valkey.credentialSecret.key` - key in the secret (default: `password`)
- `valkey.credentialSecret.autoGenerate` - set to `true` (default) to have this chart generate the password automatically in wave 2; the existing value is reused on upgrades. Set to `false` if you'd rather create the secret yourself before wave 3, following the same pattern as the other subsystem secrets above.
- `valkey.tlsSecret` - name of the TLS secret created by cert-manager for Valkey (default: `valkey-tls`)

If you deploy Valkey outside this chart instead (e.g. in a different namespace or cluster), leave `valkey.enabled: false` and set `nanogateway.redis.host` explicitly.

**Federated API Management subsystem parameters:**
- `federatedapimanagement.enabled` - set to `false` to skip this subsystem
- `federatedapimanagement.profile` - sizing profile, see [documentation](https://www.ibm.com/docs/en/api-connect/software/12.1.0?topic=profiles-api-connect-deployment-openshift)
- `federatedapimanagement.analyticsRef.name` - name of the AnalyticsCluster CR to link to
- `federatedapimanagement.analyticsRef.namespace` - namespace of the analytics CR; inherits `global.namespace` if empty
- `federatedapimanagement.adminSecret.name` - name of the FAM control-plane account secret (default: `fam-admin-secret`), used by the wave 4 `apic_fam_config` post-config role to authenticate Management against FAM
- `federatedapimanagement.adminSecret.username` - fixed username for that account (default: `administrator`)
- `federatedapimanagement.adminSecret.autoGenerate` - set to `false` to manage this secret yourself instead of having this chart generate it

Exposed routes:
- `fam.<stackHost>` - Federated API Management UI
- `api.fam.<stackHost>` - Admin API endpoint

Note: logging into the FAM UI itself (`fam.<stackHost>/controlplane/login`) uses a separate, fixed webMethods/UMC account — `Administrator` / `manage` — generated and owned by the operator in the `fam-ingress-creds` secret. This is unrelated to `federatedapimanagement.adminSecret` (the control-plane API credential Management uses to drive FAM) and is not managed by this chart. Change it from the UI after first login if needed.

## Deployment

Wave 0 (see "Platform-level Prerequisites" above) must be applied by the platform team before any of the waves below. From wave 1 onward, everything is namespace-scoped and owned by the feature team via a `deployment.wave` parameter that controls which components are deployed:
- wave 1: operators
- wave 2: certificates
- wave 3: subsystems (API manager, gateways, portals, analytics, ...)
- wave 4: post-configuration (optional, see below)

The ServiceAccounts created in wave 1 (`datapower-nano-operator`, `valkey-operator`) bind to the ClusterRoles the platform team created in wave 0, but wave 1 itself never creates any cluster-scoped object — a feature team with only namespace-scoped RBAC can run it as-is.

When using ArgoCD with this chart, you can set `deployment.wave` to the value "all" for waves 1-4, and configure ArgoCD to orchestrate the installation using the argocd.argoproj.io/sync-wave annotation that's in the Helm templates. Wave 0 is outside Helm/ArgoCD's chart lifecycle and must be applied separately (e.g. as a distinct ArgoCD Application/sync-wave owned by the platform team, or manually).

A `Makefile` at the repo root wraps the commands below (waves 0-4, wave 4 image build/push, lint/template, logs, uninstall) — run `make help` from the repo root for the full list. The manual commands are documented here for reference and for environments without `make`.

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
oc get csv -n $NAMESPACE 

# Verify the operator pods are running (pods ibm-apiconnect-*, ibm-common-service-operator-* and operand-deployment-lifecycle-manager-* must be in status Running)
oc get pod -n $NAMESPACE -l app.kubernetes.io/component=apiconnect-operator
oc get pod -n $NAMESPACE -l app.kubernetes.io/instance=ibm-common-service-operator
oc get pod -n $NAMESPACE -l app.kubernetes.io/instance=operand-deployment-lifecycle-manager

# If valkey.enabled: true (pod valkey-operator-* must be in status Running)
oc get pod -n $NAMESPACE -l name=valkey-operator

# If nanogateway.enabled: true (pod datapower-nano-operator-* must be in status Running)
oc get pod -n $NAMESPACE -l app.kubernetes.io/name=datapower-nano-operator
```

### Wave 2 - Deploy Certificates

Note: if `certificates.issuer.mode: existing` (see `certificates.issuer.*` above), make sure the referenced Issuer/ClusterIssuer already exists and is Ready before starting wave 2.

```bash
helm upgrade --install apic-certificates . \
  -f $VALUES_FILE \
  --set deployment.wave=2 \
  -n $NAMESPACE
```

**Wait for certificates to be ready (1-3 minutes):**

```bash
oc get certificate -n $NAMESPACE
```

- `mode: existing` (or explicit air-gapped/cluster-issuer setups): all certificates should show `READY: True`.
- `mode: operator` (default): the internal mTLS leaf certificates (`portal-admin-client`, `gateway-service`, etc.) stay `Pending` (`Referenced Issuer not found: apic-ingress-issuer`) — this is expected, since that issuer is only created once the `ibm-apiconnect` operator reconciles a wave 3 CR. They turn `Ready` automatically within seconds of that.

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

If `nanogateway.enabled: true`, also check the NanoGatewayCluster:
```bash
oc get nanogatewaycluster.nanogateway.apiconnect.ibm.com/ngw -n $NAMESPACE
```

If `valkey.enabled: true`, also check the ValkeyCluster (required before the Nano Gateway subsystem can become ready):
```bash
oc get valkeycluster.valkey.datapower.ibm.com/valkey -n $NAMESPACE
```

### Wave 4 - Post-configuration (optional)

Once all wave 3 subsystems are Ready, wave 4 automates the manual Cloud Manager configuration steps otherwise required, in this order:
1. Connect Cloud Manager to a mail server.
2. Create a Provider Org and the admin user that owns it.
3. Wire each deployed subsystem (analytics, wM API Gateway, Nano Gateway, wM Developer Portal, FAM) into the Cloud Manager topology and the Provider Org's Sandbox catalog.

It runs a Kubernetes Job executing the Ansible playbook shipped in `ansible/` (packaged into a ConfigMap by this chart — nothing to install on your workstation).

**Prerequisites:**
- An SMTP server reachable from the cluster, configured via `postConfig.mailServer.*` (`host`, `port`, `secure`, ...). For a quick test/demo setup, [MailPit](https://github.com/axllent/mailpit) works well
- Build and push the post-config image once (does not need to be rebuilt unless you change the Ansible roles or want a different ansible-core/kubernetes.core version):
  ```bash
  cd ansible
  docker build -t <your-registry>/iwhi/apic-postconfig:1.0.0 .
  docker push <your-registry>/iwhi/apic-postconfig:1.0.0
  ```
  On an air-gapped cluster, mirror this image the same way as the other images in this stack (see `airgapped.md`) — the image is fully self-contained (`ansible-core` + `kubernetes.core` installed at build time) and never reaches out to PyPI/Galaxy at runtime.

Set `postConfig.enabled`, `postConfig.image`, `postConfig.mailServer.*` and `postConfig.providerOrg.*` in `$VALUES_FILE` (see the parameter list below), then deploy:
```bash
helm upgrade --install apic-postconfig . \
  -f $VALUES_FILE \
  --set deployment.wave=4 \
  -n $NAMESPACE
```

**Monitor the Job:**
```bash
oc logs -f job/apic-postconfig -n $NAMESPACE
oc get job apic-postconfig -n $NAMESPACE
```

The Job is idempotent (safe to rerun in full). To rerun only part of it (e.g. after fixing a subsystem that wasn't Ready yet), set `postConfig.tags` to one or more of: `initial_config`, `porg_lur`, `analytics`, `wm_api_gateway`, `nano_gateway`, `wm_devportal`, `fam`, `porg_gateways`, `porg_portal`, `config_info`.

**Post-config parameters:**
- `postConfig.enabled` - set to `true` to deploy the wave 4 Job (disabled by default)
- `postConfig.image` - the post-config image built above (required if enabled)
- `postConfig.backoffLimit` - Job retry count on failure (default: `2`)
- `postConfig.resources` - CPU/memory limits and requests for the Job pod
- `postConfig.tags` - list of Ansible tags to run; leave empty (default) to run the full sequence
- `postConfig.mailServer.name` / `.title` / `.host` / `.port` - the mail server definition registered in Cloud Manager, connected **before** the provider org is created. **Required, no default** — e.g. `mailpit-server` / `Mail Pit Server` / `mailpit-smtp.mailpit.svc.cluster.local` / `1025` if using the MailPit instance from Prerequisites above
- `postConfig.mailServer.secure` - enable TLS/STARTTLS when talking to the SMTP server (default: `false`, matches MailPit's unauthenticated/insecure setup)
- `postConfig.providerOrg.name` / `.title` - the Provider Org to create (default: `user-demo-org` / `USER Demo Provider Org`)
- `postConfig.providerOrg.admin.username` / `.email` / `.firstName` / `.lastName` - the user this chart creates in the `api-manager-lur` registry and sets as the Provider Org's owner (all required if enabled) — not an existing user. `username` is the login id used to sign in to API Manager (e.g. `jdupont`); the password is auto-generated and stored in the `porg-lur-users-info` secret
- `postConfig.mailServer.senderName` / `.senderAddress` - "From" name/address used by API Connect for outgoing mail
- `postConfig.mailServer.apiKeyExpiresIn` / `.apiKeyMultipleUses` - generated API key lifetime (seconds) and reuse policy, set alongside the mail server in the same cloud settings call

Note: authenticated SMTP (username/password) is **not** supported yet — the API Connect mail-server `credentials` schema for that hasn't been confirmed against IBM's official documentation. MailPit and any other server accepting unauthenticated SMTP work today.

The final `config_info` step prints all subsystem endpoint URLs; passwords are never printed — it prints the `oc get secret ... | base64 -d` command to retrieve each one yourself instead.

## Uninstallation

Remove in reverse order
```bash
helm uninstall apic-subsystems -n $NAMESPACE
helm uninstall apic-certificates -n $NAMESPACE
helm uninstall apic-operators -n $NAMESPACE
```
  
Clean up secrets if needed

Wave 0 (cluster-scoped CRDs and ClusterRole/ClusterRoleBinding) is not removed by the above, and generally shouldn't be — it's shared, cluster-admin-owned setup. If you do need to tear it down (e.g. decommissioning the cluster), the platform team removes it separately:
```bash
oc delete -f cluster/crds/nanogateway-crds.yaml
oc delete -f cluster/crds/valkey-crds.yaml
oc delete clusterrole,clusterrolebinding datapower-nano-operator valkey-operator
```