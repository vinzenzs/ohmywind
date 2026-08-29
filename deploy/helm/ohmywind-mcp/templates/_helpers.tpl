{{/*
Expand the name of the chart.
*/}}
{{- define "ohmywind-mcp.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified app name (release-name aware).
*/}}
{{- define "ohmywind-mcp.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "ohmywind-mcp.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "ohmywind-mcp.labels" -}}
helm.sh/chart: {{ include "ohmywind-mcp.chart" . }}
{{ include "ohmywind-mcp.selectorLabels" . }}
app.kubernetes.io/version: {{ include "ohmywind-mcp.imageTag" . | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "ohmywind-mcp.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ohmywind-mcp.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "ohmywind-mcp.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "ohmywind-mcp.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "ohmywind-mcp.imageTag" -}}
{{- default .Chart.AppVersion .Values.image.tag }}
{{- end }}

{{/*
Name of the Secret holding OPENWIND_EDGE_SECRET, or "" when no edge secret
is configured at all.
*/}}
{{- define "ohmywind-mcp.edgeSecretName" -}}
{{- if .Values.edgeSecret.existingSecret }}
{{- .Values.edgeSecret.existingSecret }}
{{- else if .Values.edgeSecret.value }}
{{- include "ohmywind-mcp.fullname" . }}
{{- end }}
{{- end }}

{{- define "ohmywind-mcp.atlasClaimName" -}}
{{- default (printf "%s-atlas" (include "ohmywind-mcp.fullname" .)) .Values.atlas.existingClaim }}
{{- end }}
