# Custom webMethods API Gateway image

This directory holds a `Dockerfile` for building a customized `wmapigateway`
(API Gateway) image on top of the IBM-provided base image.

## When do you need a custom build?

You typically only need this if one of the following applies:

- **Adding extra JMS/messaging jars.** The base image does not ship a
  messaging provider client. If your integrations use JMS (e.g. against
  TIBCO EMS, IBM MQ, ActiveMQ, ...), the vendor's client jars must be added
  to `/opt/webmethods/IntegrationServer/lib/jars/custom/`. See the
  `tibcoems/lib/*.jar` `ADD` lines in the `Dockerfile` for an example with
  TIBCO EMS — swap these for your own messaging vendor's jars as needed.
- **Adding custom webMethods packages.** For example, custom policies,
  connectors, or other Integration Server packages that aren't part of the
  base product image. These can be added with `ADD`/`COPY` into
  `/opt/webmethods/IntegrationServer/packages/`, or installed at build time
  with `wpm` (webMethods Package Manager).
- **Removing unneeded functionality.** For example, to reduce the attack
  surface, `wpm` itself is removed from the final image in the provided
  `Dockerfile` (it is only needed at build time, not at runtime).

## Two-stage build

If your build needs tools or artifacts that shouldn't end up in the final
image — e.g. `wpm` fetching packages from a remote repository, build secrets,
or intermediate files used only to prepare custom packages — use a multi-stage
build. Do the preparation work in an earlier stage, then `COPY --from=<stage>`
only the resulting artifacts into the final stage based on `BASE_IMAGE`. This
keeps the final image free of build-time tooling and avoids leaking secrets
into its layers.

## Building the image

The base image is parameterized via the `BASE_IMAGE` build argument, defaulting
to the version currently pinned in the `Dockerfile`. Override it to rebuild
against a different base image version without editing the file.

From this directory:

```bash
docker build -t <your-registry>/<path>/ibm-apiconnect-wmapigateway-api-gateway:<tag> .
docker push <your-registry>/<path>/ibm-apiconnect-wmapigateway-api-gateway:<tag>
```

Or, to override the base image version:

```bash
docker build \
  --build-arg BASE_IMAGE=cp.icr.io/cp/apic/ibm-apiconnect-wmapigateway-api-gateway@sha256:<other-digest> \
  -t <your-registry>/<path>/ibm-apiconnect-wmapigateway-api-gateway:<tag> .
docker push <your-registry>/<path>/ibm-apiconnect-wmapigateway-api-gateway:<tag>
```

`podman` works identically in place of `docker`.

## Using the custom image in the chart

Unlike `postConfig.image` (a plain image reference set directly in
`values.yaml`), the `WMAPIGatewayCluster` CRD does not expose a single
top-level image field. Instead it has a `spec.template` list of per-microservice
overrides (`oc explain wmapigatewaycluster.spec.template`), where each entry
can override `containers[].image` for a named microservice
(`spec.template[].name`). The API Gateway microservice/container is named
`apigateway` (visible on the running pod, e.g. `wmapigateway-apigateway-0`,
container `apigateway`).

This chart exposes this override via `values.yaml`: set
`wmapigateway.customImage` to the full image reference, e.g.:

```yaml
wmapigateway:
  customImage: <your-registry>/<path>/apic-wmapigateway:<tag>
```

`templates/wmapigateway-cr.yaml` renders this into the CR as:

```yaml
spec:
  template:
  - name: apigateway
    containers:
    - name: apigateway
      image: <your-registry>/<path>/apic-wmapigateway:<tag>
```

Leave `customImage` empty (the default) to use the operator's default image.

This is independent of `wmapigateway.imageRegistry` / `global.imageRegistry`,
which only affect the images the operator pulls by default (not ones
overridden via `template`) — no need to change them just to use a custom
`apigateway` image.

If you're running air-gapped, mirroring your custom image still fits the same
flow as the rest of the operator images — see `airgapped-install.md` — except
this image is built by you rather than mirrored from an IBM CASE package.
