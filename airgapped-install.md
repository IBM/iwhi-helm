# Air-gapped Installation

## 1. Define the CASE package variables

Create the following environment variables with the installer image name and the image inventory on your host:

```bash
export CASE_NAME=ibm-apiconnect
export CASE_VERSION=8.0.0
export ARCH=amd64
export CS_CASE_NAME=ibm-cp-common-services
export CS_CASE_VERSION=4.19.1
export CS_ARCH=amd64
export EDB_CASE_NAME=ibm-cloud-native-postgresql
export EDB_CASE_VERSION=5.40.0+20260511.071333.2716
```

## 2. Download the CASE files

```bash
oc ibm-pak get $CASE_NAME --version $CASE_VERSION
oc ibm-pak get $CS_CASE_NAME --version $CS_CASE_VERSION
oc ibm-pak get $EDB_CASE_NAME --version $EDB_CASE_VERSION
```

## 3. Define the target registry

```bash
export TARGET_REGISTRY=<your-registry>
```

Make sure you're logged in to `$TARGET_REGISTRY` (e.g. `podman login $TARGET_REGISTRY` / `docker login $TARGET_REGISTRY`) before mirroring — the commands below push to it.

## 4. Generate mirror manifests

```bash
oc ibm-pak generate mirror-manifests $CASE_NAME --version $CASE_VERSION $TARGET_REGISTRY
oc ibm-pak generate mirror-manifests $CS_CASE_NAME --version $CS_CASE_VERSION $TARGET_REGISTRY
oc ibm-pak generate mirror-manifests $EDB_CASE_NAME --version $EDB_CASE_VERSION $TARGET_REGISTRY
```

## 5. Mirror the images

The commands below use `oc image mirror`, the method documented by IBM for this step. Other mirroring tools (e.g. `skopeo`, `oc mirror` v2) are equally valid — use whichever fits your environment, as long as the images end up at `$TARGET_REGISTRY` per the generated `images-mapping.txt`.

`images-mapping.txt` is a plain text file, one image per line (`source@sha256:...=destination:tag`). If you don't need every image it lists (e.g. only one EDB PostgreSQL version, or you're skipping a subsystem this chart doesn't deploy), you can edit it down to a smaller subset before mirroring — each line is independent.

```bash
oc image mirror \
  -f ~/.ibm-pak/data/mirror/$CASE_NAME/$CASE_VERSION/images-mapping.txt \
  -a $REGISTRY_AUTH_FILE \
  --filter-by-os '.*' \
  --skip-multiple-scopes \
  --max-per-registry=1

oc image mirror \
  -f ~/.ibm-pak/data/mirror/$CS_CASE_NAME/$CS_CASE_VERSION/images-mapping.txt \
  -a $REGISTRY_AUTH_FILE \
  --filter-by-os '.*' \
  --skip-multiple-scopes \
  --max-per-registry=1

oc image mirror \
  -f ~/.ibm-pak/data/mirror/$EDB_CASE_NAME/$EDB_CASE_VERSION/images-mapping.txt \
  -a $REGISTRY_AUTH_FILE \
  --filter-by-os '.*' \
  --skip-multiple-scopes \
  --max-per-registry=1
```

## 6. Create the ImageContentSourcePolicy

This instructs the cluster to pull the images from your local registry:

```bash
oc apply -f ~/.ibm-pak/data/mirror/$CASE_NAME/$CASE_VERSION/image-content-source-policy.yaml
oc apply -f ~/.ibm-pak/data/mirror/$CS_CASE_NAME/$CS_CASE_VERSION/image-content-source-policy.yaml
oc apply -f ~/.ibm-pak/data/mirror/$EDB_CASE_NAME/$EDB_CASE_VERSION/image-content-source-policy.yaml
```

Verify that the ImageContentSourcePolicy resource was created:

```bash
oc get imageContentSourcePolicy
```

Wait for all cluster nodes to be ready:

```bash
oc get MachineConfigPool -w
```

## 7. Update the cluster's global pull secret

The CatalogSource pods in `openshift-marketplace` need this to pull the mirrored catalog index images from the target registry (without this, CatalogSource pods fail with `ImagePullBackOff` / `unauthorized` even though the images exist in the target registry):

```bash
oc get secret pull-secret -n openshift-config -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d > pull-secret.json
```

Merge the target registry credentials into `pull-secret.json` (add an entry under `.auths` for `$TARGET_REGISTRY`'s host, reusing the same credentials as your local registry pull secret), then apply it:

```bash
oc set data secret/pull-secret -n openshift-config --from-file=.dockerconfigjson=pull-secret.json
```

This triggers a MachineConfigPool rollout on all nodes (propagates the new pull secret to `/var/lib/kubelet/config.json`); wait for it to complete before continuing:

```bash
oc get MachineConfigPool -w
```

## 8. Apply the catalog sources

```bash
oc apply -f ~/.ibm-pak/data/mirror/${CASE_NAME}/${CASE_VERSION}/catalog-sources.yaml
oc apply -f ~/.ibm-pak/data/mirror/${CS_CASE_NAME}/${CS_CASE_VERSION}/catalog-sources.yaml
oc apply -f ~/.ibm-pak/data/mirror/${EDB_CASE_NAME}/${EDB_CASE_VERSION}/catalog-sources.yaml
```

Note: use these generated files, not `charts/apic/catalog-sources/12.1.1.0/catalog-sources-apiconnect.yaml` in this repo — that one points at the public `icr.io` images, while the files generated here point at `$TARGET_REGISTRY`.

## 9. Deploy the apic chart

At this point the cluster can pull the operator images from `$TARGET_REGISTRY`. Two more things are specific to running this chart air-gapped:

- **cert-manager operator**: comes from Red Hat's own catalog (`redhat-operators`), separate from the CASE packages mirrored above — see the "Ensure cert manager is deployed" section of `charts/apic/README.md`. Mirror it the same way if `redhat-operators` isn't already available on this cluster.
- **`postConfig.image` (wave 4)**: this chart's own post-configuration image, not part of any CASE package. Build and mirror it separately — see "Wave 4 - Post-configuration" in `charts/apic/README.md`.

Set `global.imageRegistry` (and `nanogateway.imageRegistry` if `nanogateway.enabled: true`) to `$TARGET_REGISTRY`'s path in your values file — see `charts/apic/examples/values-localissuer-ag.yaml` for a complete example — then follow the deployment steps in `charts/apic/README.md`.
