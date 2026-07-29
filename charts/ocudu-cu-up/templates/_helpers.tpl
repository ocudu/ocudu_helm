{{/*
SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
SPDX-License-Identifier: BSD-3-Clause-Open-MPI
*/}}

{{/*
Expand the name of the chart.
*/}}
{{- define "ocudu-cu-up.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "ocudu-cu-up.fullname" -}}
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
{{- define "ocudu-cu-up.mainConfigmapName" -}}
{{- with .Values.configmap }}
  {{- with .main }}
    {{- if .nameOverride }}
      {{- .nameOverride | trunc 63 | trimSuffix "-" -}}
    {{- else }}
      {{- printf "%s-config" (include "ocudu-cu-up.fullname" $) | trunc 63 | trimSuffix "-" -}}
    {{- end }}
  {{- else }}
    {{- printf "%s-config" (include "ocudu-cu-up.fullname" $) | trunc 63 | trimSuffix "-" -}}
  {{- end }}
{{- else }}
  {{- printf "%s-config" (include "ocudu-cu-up.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end }}
{{- end }}

{{/*
O1 mode configmap (values.o1Config)
*/}}
{{- define "ocudu-cu-up.o1ConfigmapName" -}}
{{- with .Values.configmap }}
  {{- with .o1 }}
    {{- if .nameOverride }}
      {{- .nameOverride | trunc 63 | trimSuffix "-" -}}
    {{- else }}
      {{- printf "%s-o1-config" (include "ocudu-cu-up.fullname" $) | trunc 63 | trimSuffix "-" -}}
    {{- end }}
  {{- else }}
    {{- printf "%s-o1-config" (include "ocudu-cu-up.fullname" $) | trunc 63 | trimSuffix "-" -}}
  {{- end }}
{{- else }}
  {{- printf "%s-o1-config" (include "ocudu-cu-up.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end }}
{{- end }}

{{/*
Entrypoint script configmap
*/}}
{{- define "ocudu-cu-up.entrypointConfigmapName" -}}
{{- with .Values.configmap }}
  {{- with .entrypoint }}
    {{- if .nameOverride }}
      {{- .nameOverride | trunc 63 | trimSuffix "-" -}}
    {{- else }}
      {{- printf "%s-entrypoint" (include "ocudu-cu-up.fullname" $) | trunc 63 | trimSuffix "-" -}}
    {{- end }}
  {{- else }}
    {{- printf "%s-entrypoint" (include "ocudu-cu-up.fullname" $) | trunc 63 | trimSuffix "-" -}}
  {{- end }}
{{- else }}
  {{- printf "%s-entrypoint" (include "ocudu-cu-up.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "ocudu-cu-up.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "ocudu-cu-up.labels" -}}
helm.sh/chart: {{ include "ocudu-cu-up.chart" . }}
{{ include "ocudu-cu-up.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "ocudu-cu-up.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ocudu-cu-up.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "ocudu-cu-up.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "ocudu-cu-up.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the image path for the passed in image field (tag or sha256: digest).
Call with any image dict, e.g. .Values.image or (.Values.o1).o1Adapter.image
*/}}
{{- define "ocudu-cu-up.image" -}}
{{- if eq (substr 0 7 (.tag | toString)) "sha256:" -}}
{{- printf "%s@%s" .repository (.tag | toString) -}}
{{- else -}}
{{- printf "%s:%s" .repository (.tag | toString) -}}
{{- end -}}
{{- end -}}

{{/*
NETCONF-over-TLS port. Fixed by the netconf-server image, which is passed no port
flag — this is a single source of truth for the templates, not a tunable.
See the o1Port note in values-o1.yaml.
*/}}
{{- define "ocudu-cu-up.o1.tlsPort" -}}6513{{- end -}}
