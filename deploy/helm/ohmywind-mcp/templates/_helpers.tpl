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

{{/*
Name of the Secret holding OPENWIND_API_TOKEN, or "" when /mcp is open.
*/}}
{{- define "ohmywind-mcp.apiTokenSecretName" -}}
{{- if .Values.auth.existingSecret }}
{{- .Values.auth.existingSecret }}
{{- else if .Values.auth.token }}
{{- include "ohmywind-mcp.fullname" . }}
{{- end }}
{{- end }}

{{/*
True when the chart itself renders a Secret (any inline secret value given).
*/}}
{{- define "ohmywind-mcp.rendersSecret" -}}
{{- if or (and .Values.edgeSecret.value (not .Values.edgeSecret.existingSecret)) (and .Values.auth.token (not .Values.auth.existingSecret)) }}true{{ end }}
{{- end }}

{{- define "ohmywind-mcp.atlasClaimName" -}}
{{- default (printf "%s-atlas" (include "ohmywind-mcp.fullname" .)) .Values.atlas.existingClaim }}
{{- end }}

{{/*
Web component: name, labels and image tag.
*/}}
{{- define "ohmywind-mcp.web.fullname" -}}
{{- printf "%s-web" (include "ohmywind-mcp.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "ohmywind-mcp.web.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ohmywind-mcp.name" . }}-web
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "ohmywind-mcp.web.labels" -}}
helm.sh/chart: {{ include "ohmywind-mcp.chart" . }}
{{ include "ohmywind-mcp.web.selectorLabels" . }}
app.kubernetes.io/component: web
app.kubernetes.io/version: {{ include "ohmywind-mcp.web.imageTag" . | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "ohmywind-mcp.web.imageTag" -}}
{{- default .Chart.AppVersion .Values.web.image.tag }}
{{- end }}
