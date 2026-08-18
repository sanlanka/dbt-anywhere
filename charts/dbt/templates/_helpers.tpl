{{/*
Connection env vars shared by the dbt pod. profiles.yml reads every one of
these, so the same profile works locally and in-cluster.
*/}}
{{- define "dbt.pgEnv" -}}
- name: DBT_PG_HOST
  value: {{ .Values.postgres.service | quote }}
- name: DBT_PG_PORT
  value: "5432"
- name: DBT_PG_USER
  value: {{ .Values.postgres.user | quote }}
- name: DBT_PG_PASSWORD
  value: {{ .Values.postgres.password | quote }}
- name: DBT_PG_DATABASE
  value: {{ .Values.postgres.database | quote }}
- name: DBT_PG_SCHEMA
  value: {{ .Values.postgres.schema | quote }}
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

{{/*
Matching hostPath volume. Indented for a pod's `volumes:` list.
*/}}
{{- define "dbt.projectVolume" -}}
{{- if and .Values.hostMount.enabled .Values.hostMount.hostPath }}
- name: project
  hostPath:
    path: {{ .Values.hostMount.hostPath | quote }}
    type: Directory
{{- end }}
{{- end -}}
