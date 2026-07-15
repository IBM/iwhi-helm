ARG BASE_IMAGE=cp.icr.io/cp/apic/ibm-apiconnect-wmapigateway-api-gateway@sha256:505c72829b9063f025387a6563249249ff2192a5a071272a206511629f4b5f0b
FROM ${BASE_IMAGE} AS base

# Addition of the JMS jar
# Tibco EMS jars here, can be replaced with other messaging vendor jars
# ADD --chown=1724:0 tibcoems/lib/jms-2.0.jar /opt/webmethods/IntegrationServer/lib/jars/custom/jms-2.0.jar
# ADD --chown=1724:0 tibcoems/lib/tibemsd_sec.jar /opt/webmethods/IntegrationServer/lib/jars/custom/tibemsd_sec.jar
# ADD --chown=1724:0 tibcoems/lib/tibjms.jar /opt/webmethods/IntegrationServer/lib/jars/custom/tibjms.jar

# Addition of custom webMethods packages (custom policies, etc.)
# Note: wpm (webMethods Package Manager) can also be used to install custom packages
# ADD --chown=1724:0 ./myPackage /opt/webmethods/IntegrationServer/packages/myPackage

# Removal of unused features
# wpm (webMethods Package Manager) is only needed at build time
RUN rm -rf /opt/webmethods/wpm

# If needed, a second stage can be added in the build to flatten the layers, avoid leakage of build secrets, etc.

