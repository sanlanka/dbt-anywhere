{{/*
BigQuery keyfile mount (optional). Indented for a container's `volumeMounts:`.
*/}}
{{- define "dbt.keyfileMount" -}}
{{- if .Values.warehouse.keyfileSecret }}
- name: warehouse-keyfile
  mountPath: {{ .Values.warehouse.keyfileMountPath | quote }}
  readOnly: true
{{- end }}
{{- end -}}

{{- define "dbt.keyfileVolume" -}}
{{- if .Values.warehouse.keyfileSecret }}
- name: warehouse-keyfile
  secret:
    secretName: {{ .Values.warehouse.keyfileSecret | quote }}
{{- end }}
{{- end -}}

{{/*
Project hostPath mount. Indented for a container's `volumeMounts:` list.
*/}}
{{- define "dbt.projectMount" -}}
{{- if and .Values.hostMount.enabled .Values.hostMount.hostPath }}
- name: project
  mountPath: {{ .Values.hostMount.mountPath | quote }}
{{- end }}
{{- end -}}

{{- define "dbt.projectVolume" -}}
{{- if and .Values.hostMount.enabled .Values.hostMount.hostPath }}
- name: project
  hostPath:
    path: {{ .Values.hostMount.hostPath | quote }}
    type: Directory
{{- end }}
{{- end -}}
