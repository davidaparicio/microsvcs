{{- define "microsvcs.fullname" -}}
{{- printf "%s-%s" .Values.name .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "microsvcs.name" -}}
{{- .Values.name }}
{{- end }}

{{- define "microsvcs.labels" -}}
app.kubernetes.io/name: {{ .Values.name }}
app.kubernetes.io/instance: {{ .Values.name }}-{{ .Values.environment }}
app.kubernetes.io/part-of: microsvcs
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
environment: {{ .Values.environment }}
{{- end }}

{{- define "microsvcs.selectorLabels" -}}
app.kubernetes.io/name: {{ .Values.name }}
{{- end }}
