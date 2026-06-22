{{/*
SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
SPDX-License-Identifier: BSD-3-Clause-Open-MPI
*/}}

{{/*
Expand the name of the chart.
*/}}
{{- define "ocudu-du.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "ocudu-du.fullname" -}}
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

{{/*
Main configmap name
*/}}
{{- define "ocudu-du.mainConfigmapName" -}}
{{- with .Values.configmap }}
  {{- with .main }}
    {{- if .nameOverride }}
      {{- .nameOverride | trunc 63 | trimSuffix "-" -}}
    {{- else }}
      {{- printf "%s-config" (include "ocudu-du.fullname" $) | trunc 63 | trimSuffix "-" -}}
    {{- end }}
  {{- else }}
    {{- printf "%s-config" (include "ocudu-du.fullname" $) | trunc 63 | trimSuffix "-" -}}
  {{- end }}
{{- else }}
  {{- printf "%s-config" (include "ocudu-du.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end }}
{{- end }}

{{/*
O1 mode configmap (values.o1Config)
*/}}
{{- define "ocudu-du.o1ConfigmapName" -}}
{{- with .Values.configmap }}
  {{- with .o1 }}
    {{- if .nameOverride }}
      {{- .nameOverride | trunc 63 | trimSuffix "-" -}}
    {{- else }}
      {{- printf "%s-o1-config" (include "ocudu-du.fullname" $) | trunc 63 | trimSuffix "-" -}}
    {{- end }}
  {{- else }}
    {{- printf "%s-o1-config" (include "ocudu-du.fullname" $) | trunc 63 | trimSuffix "-" -}}
  {{- end }}
{{- else }}
  {{- printf "%s-o1-config" (include "ocudu-du.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end }}
{{- end }}

{{/*
Entrypoint script configmap
*/}}
{{- define "ocudu-du.entrypointConfigmapName" -}}
{{- with .Values.configmap }}
  {{- with .entrypoint }}
    {{- if .nameOverride }}
      {{- .nameOverride | trunc 63 | trimSuffix "-" -}}
    {{- else }}
      {{- printf "%s-entrypoint" (include "ocudu-du.fullname" $) | trunc 63 | trimSuffix "-" -}}
    {{- end }}
  {{- else }}
    {{- printf "%s-entrypoint" (include "ocudu-du.fullname" $) | trunc 63 | trimSuffix "-" -}}
  {{- end }}
{{- else }}
  {{- printf "%s-entrypoint" (include "ocudu-du.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "ocudu-du.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "ocudu-du.labels" -}}
helm.sh/chart: {{ include "ocudu-du.chart" . }}
{{ include "ocudu-du.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "ocudu-du.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ocudu-du.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "ocudu-du.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "ocudu-du.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the image path
*/}}
{{- define "ocudu-du.image" -}}
{{- if eq (substr 0 7 (.tag | toString)) "sha256:" -}}
{{- printf "%s@%s" .repository (.tag | toString) -}}
{{- else -}}
{{- printf "%s:%s" .repository (.tag | toString) -}}
{{- end -}}
{{- end -}}

{{/*
Create the image path for the passed in image field of netconf-server image
*/}}
{{- define "ocudu-du.o1.netconfServer.image" -}}
{{- if eq (substr 0 7 (.tag | toString)) "sha256:" -}}
{{- printf "%s@%s" .repository (.tag | toString) -}}
{{- else -}}
{{- printf "%s:%s" .repository (.tag | toString) -}}
{{- end -}}
{{- end -}}

{{/*
Create the image path for the passed in image field of o1-adapter image
*/}}
{{- define "ocudu-du.o1.o1Adapter.image" -}}
{{- if eq (substr 0 7 (.tag | toString)) "sha256:" -}}
{{- printf "%s@%s" .repository (.tag | toString) -}}
{{- else -}}
{{- printf "%s:%s" .repository (.tag | toString) -}}
{{- end -}}
{{- end -}}
