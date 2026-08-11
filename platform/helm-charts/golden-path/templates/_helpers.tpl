{{- define "golden-path.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "golden-path.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "golden-path.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "golden-path.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" -}}
{{- end -}}

{{- define "golden-path.selectorLabels" -}}
app.kubernetes.io/name: {{ include "golden-path.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "golden-path.labels" -}}
helm.sh/chart: {{ include "golden-path.chart" . }}
{{ include "golden-path.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: internal-developer-platform
{{- end -}}

{{- define "golden-path.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "golden-path.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "golden-path.image" -}}
{{- $image := .Values.image -}}
{{- if $image.digest -}}
{{- if $image.tag -}}
{{- printf "%s:%s@%s" $image.repository $image.tag $image.digest -}}
{{- else -}}
{{- printf "%s@%s" $image.repository $image.digest -}}
{{- end -}}
{{- else -}}
{{- printf "%s:%s" $image.repository $image.tag -}}
{{- end -}}
{{- end -}}

{{- define "golden-path.configChecksum" -}}
{{- if and .Values.config.create .Values.config.data -}}
{{- toYaml .Values.config.data | sha256sum -}}
{{- end -}}
{{- end -}}
