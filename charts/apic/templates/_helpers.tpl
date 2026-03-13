{{/*
=============================================================================
IBM webMethods Hybrid Integration (IWHI) – Helm Helper Templates
=============================================================================
*/}}

{{/*
Expand the chart name.
*/}}
{{- define "apic.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Resolve the target namespace.
*/}}
{{- define "apic.namespace" -}}
{{- .Values.global.namespace }}
{{- end }}

{{/*
Resolve the image registry for a subsystem.
Falls back to global.imageRegistry if the subsystem-level value is empty.
Usage: {{ include "apic.imageRegistry" (dict "subsystem" .Values.wmapigateway "global" .Values.global) }}
*/}}
{{- define "apic.imageRegistry" -}}
{{- if .subsystem.imageRegistry -}}
{{- .subsystem.imageRegistry -}}
{{- else -}}
{{- .global.imageRegistry -}}
{{- end -}}
{{- end }}

{{/*
Resolve the storage class for a subsystem.
Falls back to global.storageClass if the subsystem-level value is empty.
Usage: {{ include "apic.storageClass" (dict "subsystem" .Values.management "global" .Values.global) }}
*/}}
{{- define "apic.storageClass" -}}
{{- if .subsystem.storageClass -}}
{{- .subsystem.storageClass -}}
{{- else -}}
{{- .global.storageClass -}}
{{- end -}}
{{- end }}

{{/*
Resolve the analytics ref namespace for a subsystem.
Falls back to global.namespace if the analyticsRef.namespace value is empty.
Usage: {{ include "apic.analyticsRefNamespace" (dict "ref" .Values.devportal.analyticsRef "global" .Values.global) }}
*/}}
{{- define "apic.analyticsRefNamespace" -}}
{{- if .ref.namespace -}}
{{- .ref.namespace -}}
{{- else -}}
{{- .global.namespace -}}
{{- end -}}
{{- end }}

{{/*
Common labels applied to every resource.
*/}}
{{- define "apic.labels" -}}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: ibm-apiconnect
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{/*
Resolve the certificate issuer name.
Returns the provided name if set, otherwise returns the default created issuer name.
Usage: {{ include "apic.issuerName" . }}
*/}}
{{- define "apic.issuerName" -}}
{{- if .Values.certificates.issuer.name -}}
{{- .Values.certificates.issuer.name -}}
{{- else -}}
apic-issuer
{{- end -}}
{{- end }}

{{/*
Resolve the certificate issuer kind.
Usage: {{ include "apic.issuerKind" . }}
*/}}
{{- define "apic.issuerKind" -}}
{{- .Values.certificates.issuer.kind -}}
{{- end }}

{{/*
Determine if issuer should be created.
Returns true if name is empty (meaning we need to create it).
Usage: {{ include "apic.createIssuer" . }}
*/}}
{{- define "apic.createIssuer" -}}
{{- if not .Values.certificates.issuer.name -}}
true
{{- end -}}
{{- end }}

{{/*
Resolve the cert-manager annotation key for the issuer.
Returns "cert-manager.io/cluster-issuer" if kind is ClusterIssuer, otherwise "cert-manager.io/issuer".
Usage: {{ include "apic.issuerAnnotation" . }}
*/}}
{{- define "apic.issuerAnnotation" -}}
{{- if eq (include "apic.issuerKind" .) "ClusterIssuer" -}}
cert-manager.io/cluster-issuer
{{- else -}}
cert-manager.io/issuer
{{- end -}}
{{- end }}
