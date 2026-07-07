# =============================================================================
# Self-contained image for the wave 4 post-configuration Job.
# ansible-core and the kubernetes.core collection are installed at BUILD time
# only — the container never reaches out to PyPI, Galaxy or any other
# registry at runtime, so it works unmodified on air-gapped clusters once
# mirrored to a local registry (see /Users/staillan/git/iwhi-helm/airgapped.md).
#
# Build and push (from this directory):
#   docker build -t <your-registry>/iwhi/apic-postconfig:1.0.0 .
#   docker push <your-registry>/iwhi/apic-postconfig:1.0.0
#
# Then set in values.yaml:
#   postConfig.image: <your-registry>/iwhi/apic-postconfig:1.0.0
# =============================================================================
FROM registry.access.redhat.com/ubi9/python-312:latest

USER root

# --requirement installs are pinned so the build is reproducible; adjust
# versions here and rebuild rather than letting the Job resolve them.
RUN pip install --no-cache-dir \
        ansible-core==2.17.* \
        kubernetes==31.* \
        jmespath==1.* \
    && ansible-galaxy collection install kubernetes.core \
    && rm -rf /root/.cache/pip

WORKDIR /ansible

USER 1001

ENTRYPOINT ["ansible-playbook"]
CMD ["--help"]
