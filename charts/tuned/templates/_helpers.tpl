{{/*
SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
SPDX-License-Identifier: BSD-3-Clause-Open-MPI
*/}}

{{- define "tuned.labels" -}}
app.kubernetes.io/name: tuned
app.kubernetes.io/instance: {{ .Release.Name }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{- define "tuned.selectorLabels" -}}
app.kubernetes.io/name: tuned
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
