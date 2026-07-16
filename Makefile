# =============================================================================
# IBM API Connect (apic chart) – convenience targets for the wave-based
# deployment described in charts/apic/README.md.
#
# Override any variable on the command line, e.g.:
#   make wave1 NAMESPACE=apic VALUES_FILE=charts/apic/examples/values-localissuer.yaml
# =============================================================================

CHART_DIR      := charts/apic
NAMESPACE      ?= apic
VALUES_FILE    ?= $(CHART_DIR)/examples/values-localissuer.yaml
POSTCONFIG_TAG ?= 1.0.0

# Cluster and container-build CLIs. Override for other environments, e.g.:
#   make wave1 OC=kubectl
#   make postconfig-build PODMAN=docker
OC     ?= oc
PODMAN ?= podman

# Extra --set flags appended to every helm invocation, e.g.:
#   make lint EXTRA_ARGS="--set nanogateway.skipGatewayApiCheck=true"
EXTRA_ARGS     ?=

# Internal OpenShift ImageStream reference used by templates/postconfig-job.yaml.
# Override REGISTRY_HOST if you push postConfig.image to an external registry
# instead (see charts/apic/ansible/Dockerfile). Only resolves automatically
# with OC=oc (this route is OpenShift-specific); set it explicitly otherwise.
REGISTRY_HOST  ?= $(shell $(OC) get route default-route -n openshift-image-registry -o jsonpath='{.spec.host}' 2>/dev/null)
POSTCONFIG_IMAGE ?= $(REGISTRY_HOST)/$(NAMESPACE)/apic-postconfig:$(POSTCONFIG_TAG)

.PHONY: help lint template \
	wave0 wave1 wave2 wave3 wave4 wave-all \
	postconfig-imagestream postconfig-build postconfig-push postconfig-image \
	postconfig-logs postconfig-status postconfig-rerun \
	uninstall clean

help:
	@echo "Targets:"
	@echo "  lint                    - helm lint the apic chart"
	@echo "  template WAVE=<0|1|2|3|4|all> - render the chart for a given wave (no cluster changes)"
	@echo "  wave0                   - platform team: cluster-scoped CRDs + ClusterRole/ClusterRoleBinding (oc apply, no Helm)"
	@echo "  wave1                   - feature team: deploy operators (wave 1, namespace-scoped)"
	@echo "  wave2                   - deploy certificates (wave 2)"
	@echo "  wave3                   - deploy subsystems (wave 3)"
	@echo "  wave4                   - deploy post-configuration (wave 4, requires postconfig-image)"
	@echo "  wave-all                - deploy everything in one release (ArgoCD-style, wave=all)"
	@echo "  postconfig-build        - podman build the wave 4 image (linux/amd64)"
	@echo "  postconfig-push         - podman login + push the wave 4 image to the internal registry"
	@echo "  postconfig-logs         - follow the wave 4 Job logs"
	@echo "  postconfig-status       - show the wave 4 Job status"
	@echo "  postconfig-rerun        - delete and redeploy the wave 4 Job (picks up ansible/ changes)"
	@echo "  uninstall                - helm uninstall all apic releases in \$$NAMESPACE"
	@echo ""
	@echo "Variables (override with VAR=value):"
	@echo "  NAMESPACE=$(NAMESPACE)"
	@echo "  VALUES_FILE=$(VALUES_FILE)"
	@echo "  OC=$(OC)"
	@echo "  PODMAN=$(PODMAN)"
	@echo "  POSTCONFIG_IMAGE=$(POSTCONFIG_IMAGE)"

lint:
	helm lint $(CHART_DIR) -f $(VALUES_FILE) --set deployment.wave=1 $(EXTRA_ARGS)

template:
	helm template test $(CHART_DIR) -f $(VALUES_FILE) --set deployment.wave=$(WAVE) $(EXTRA_ARGS)

# Wave 0 — platform team only. Cluster-scoped objects (CRDs, ClusterRole,
# ClusterRoleBinding), applied directly with oc/kubectl, outside Helm.
# Requires cluster-admin-level privileges; the feature team never runs this.
# Safe to re-run (oc apply is idempotent); CRD updates on chart upgrades also
# go through this target — re-run it whenever cluster/crds/*.yaml changes.
wave0:
	$(OC) apply -f $(CHART_DIR)/cluster/crds/nanogateway-crds.yaml
	$(OC) apply -f $(CHART_DIR)/cluster/crds/valkey-crds.yaml
	NAMESPACE=$(NAMESPACE) envsubst '$$NAMESPACE' < $(CHART_DIR)/cluster/rbac/nanogateway-operator.yaml | $(OC) apply -f -
	NAMESPACE=$(NAMESPACE) envsubst '$$NAMESPACE' < $(CHART_DIR)/cluster/rbac/valkey-operator.yaml | $(OC) apply -f -

wave1:
	helm upgrade --install apic-operators $(CHART_DIR) \
		-f $(VALUES_FILE) --set deployment.wave=1 -n $(NAMESPACE) $(EXTRA_ARGS)

wave2:
	helm upgrade --install apic-certificates $(CHART_DIR) \
		-f $(VALUES_FILE) --set deployment.wave=2 -n $(NAMESPACE) $(EXTRA_ARGS)

wave3:
	helm upgrade --install apic-subsystems $(CHART_DIR) \
		-f $(VALUES_FILE) --set deployment.wave=3 -n $(NAMESPACE) $(EXTRA_ARGS)

# Wave 4 requires postConfig.image to be set — either bake it into
# VALUES_FILE, or pass it here: make wave4 POSTCONFIG_IMAGE=...
wave4:
	helm upgrade --install apic-postconfig $(CHART_DIR) \
		-f $(VALUES_FILE) --set deployment.wave=4 \
		--set postConfig.enabled=true \
		--set postConfig.image=$(POSTCONFIG_IMAGE) \
		-n $(NAMESPACE) $(EXTRA_ARGS)

wave-all:
	helm upgrade --install apic $(CHART_DIR) \
		-f $(VALUES_FILE) --set deployment.wave=all -n $(NAMESPACE) $(EXTRA_ARGS)

# --- Wave 4 image lifecycle ---------------------------------------------

postconfig-build:
	cd $(CHART_DIR)/ansible && $(PODMAN) build --platform linux/amd64 -t $(POSTCONFIG_IMAGE) .

# oc/kubectl `create token` both work for the ServiceAccount login below.
postconfig-push:
	$(PODMAN) push $(POSTCONFIG_IMAGE)

# --- Wave 4 Job lifecycle -----------------------------------------------

postconfig-logs:
	$(OC) logs -f job/apic-postconfig -n $(NAMESPACE) -c ansible-playbook

postconfig-status:
	$(OC) get job apic-postconfig -n $(NAMESPACE)
	$(OC) get pod -n $(NAMESPACE) -l app.kubernetes.io/name=apic-postconfig

# Jobs are immutable once created: delete before re-running (e.g. after
# editing ansible/ roles, which only need a ConfigMap regen via `helm
# upgrade`, not a new image).
postconfig-rerun:
	$(OC) delete job apic-postconfig -n $(NAMESPACE) --ignore-not-found
	$(MAKE) wave4

# --- Cleanup --------------------------------------------------------------

uninstall:
	-helm uninstall apic-postconfig -n $(NAMESPACE)
	-helm uninstall apic-subsystems -n $(NAMESPACE)
	-helm uninstall apic-certificates -n $(NAMESPACE)
	-helm uninstall apic-operators -n $(NAMESPACE)
