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
Main container image reference, with the tag defaulting to the chart appVersion.
Without the fallback an unset image.tag renders "<repository>:", which is not a
valid image reference and leaves the chart with no usable default version.
*/}}
{{- define "ocudu-du.mainImage" -}}
{{- $image := dict "repository" .Values.image.repository "tag" (default .Chart.AppVersion .Values.image.tag) -}}
{{- include "ocudu-du.image" $image -}}
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

{{/*
Fail unless resources.requests and resources.limits both set cpu and memory.
*/}}
{{- define "ocudu-du.requireResources" -}}
{{- $resources := .Values.resources | default dict -}}
{{- range $kind := list "requests" "limits" -}}
{{- range $name := list "cpu" "memory" -}}
{{- $_ := required (printf "resources.%s.%s is required (set cpu and memory in both resources.requests and resources.limits)" $kind $name) (get (get $resources $kind | default dict) $name) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Name of the headless service that publishes this pod's outer IPsec address.
A cluster IP service cannot be used: it forwards only the ports it declares, and it
rewrites addresses, which breaks the peer address detection IKE relies on.
*/}}
{{- define "ocudu-du.ipsec.serviceName" -}}
{{- printf "%s-ipsec" (include "ocudu-du.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Name of the configmap holding the IPsec configuration.
*/}}
{{- define "ocudu-du.ipsec.configmapName" -}}
{{- printf "%s-ipsec-config" (include "ocudu-du.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Sidecar image reference.
*/}}
{{- define "ocudu-du.ipsec.image" -}}
{{- include "ocudu-du.image" .Values.ipsec.image -}}
{{- end -}}

{{/*
Every application config document joined into one string, so it can be searched.
*/}}
{{- define "ocudu-du.ipsec.configBlob" -}}
{{- range $name, $doc := .Values.config }}
{{ $doc }}
{{- end }}
{{- end -}}

{{/*
Pull one section out of an application config document, by key name.

The config is an opaque string rather than a structure, so this works on text: it finds a
line whose only content is "<key>:" and returns every following line indented further than
that one. Comment lines are dropped, so a value that only appears in a comment cannot
satisfy a check.

Reading whole documents instead would be wrong in both directions. A wildcard bind address
is correct under some keys and is the plaintext bypass under the F1 ones, and an address
mentioned anywhere at all would otherwise look like a binding.

Call with: dict "blob" <string> "key" <string>
*/}}
{{- define "ocudu-du.ipsec.section" -}}
{{- $key := printf "%s:" .key -}}
{{- $out := list -}}
{{- $collect := false -}}
{{- $indent := 0 -}}
{{- range $line := splitList "\n" .blob -}}
  {{- $text := trim $line -}}
  {{- if and (ne $text "") (not (hasPrefix "#" $text)) -}}
    {{- $width := len (regexFind "^ *" $line) -}}
    {{- if $collect -}}
      {{- if le $width $indent -}}
        {{- $collect = false -}}
      {{- else -}}
        {{- $out = append $out $text -}}
      {{- end -}}
    {{- end -}}
    {{- if eq $text $key -}}
      {{- $collect = true -}}
      {{- $indent = $width -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- join "\n" $out -}}
{{- end -}}

{{/*
Refuse to render anything that would leave a protected interface unprotected.

Every one of these is a way the tunnel can end up configured but bypassed, which looks
like success and is not. A failed install is recoverable; plaintext on the wire is not.
*/}}
{{- define "ocudu-du.ipsec.validate" -}}
{{- if .Values.ipsec.enabled -}}

{{- if .Values.network.hostNetwork -}}
{{- fail "ipsec.enabled needs network.hostNetwork to be false: with host networking the pod shares the node's network namespace, so it is not a separate tunnel endpoint and its traffic cannot be told apart from the node's" -}}
{{- end -}}

{{- if (.Values.o1).enable_ocudu_o1 -}}
{{- fail "ipsec.enabled cannot be combined with o1.enable_ocudu_o1: in O1 mode the application config is written at runtime, so the chart cannot check that the application binds to the protected addresses, and the O1 interface can move it off them later" -}}
{{- end -}}

{{- if not (semverCompare ">=1.29.0-0" .Capabilities.KubeVersion.Version) -}}
{{- fail (printf "ipsec.enabled needs Kubernetes 1.29 or newer, and this cluster reports %s: the sidecar has to start before the application and stop after it, which only a sidecar init container guarantees" .Capabilities.KubeVersion.Version) -}}
{{- end -}}

{{- if .Values.f1cService.enabled -}}
{{- fail "ipsec.enabled needs f1cService.enabled to be false: that service publishes an unprotected path to the F1-C port on the pod address, which is the bypass this feature exists to close" -}}
{{- end -}}
{{- if .Values.f1uService.enabled -}}
{{- fail "ipsec.enabled needs f1uService.enabled to be false: that service publishes an unprotected path to the F1-U port on the pod address, which is the bypass this feature exists to close" -}}
{{- end -}}

{{- if and (not .Values.networkPolicy.enabled) (not .Values.ipsec.allowWithoutNetworkPolicy) -}}
{{- fail "ipsec.enabled needs networkPolicy.enabled to be true: without a policy the application can still address the peer directly and send in clear, and nothing inside the pod can stop it. Set ipsec.allowWithoutNetworkPolicy to true only where unprotected traffic is blocked some other way" -}}
{{- end -}}

{{- if not .Values.ipsec.certSecret -}}
{{- fail "ipsec.certSecret is required: it holds tls.crt, tls.key and ca.crt, and without them the peer cannot be authenticated" -}}
{{- end -}}
{{- if and .Values.ipsec.certManager.enabled (not .Values.ipsec.certManager.issuerRef.name) -}}
{{- fail "ipsec.certManager.issuerRef.name is required when ipsec.certManager.enabled is true: without an issuer the certificate is never signed and the secret is never written" -}}
{{- end -}}
{{- if not .Values.ipsec.localId -}}
{{- fail "ipsec.localId is required: it is the identity this pod presents, and it has to match the certificate in ipsec.certSecret" -}}
{{- end -}}
{{- if not .Values.ipsec.peers -}}
{{- fail "ipsec.peers is empty: there is no one to build an association with, so the sidecar would run and protect nothing" -}}
{{- end -}}
{{- range $peerName, $peer := .Values.ipsec.peers -}}
{{- if not $peer.id -}}
{{- fail (printf "ipsec.peers.%s.id is required: without it any certificate signed by the CA would be accepted, from any peer" $peerName) -}}
{{- end -}}
{{- end -}}
{{- if not (has .Values.ipsec.encapsulation (list "udp" "native")) -}}
{{- fail (printf "ipsec.encapsulation is %q, and the only values are \"udp\" and \"native\"" .Values.ipsec.encapsulation) -}}
{{- end -}}

{{- if eq (int .Values.ipsec.ike.replayWindow) 0 -}}
{{- fail "ipsec.ike.replayWindow is 0, which switches replay protection off: a captured packet could then be replayed and accepted. Give it a width instead" -}}
{{- end -}}
{{- if not .Values.ipsec.connections -}}
{{- fail "ipsec.connections is empty: the sidecar would run and protect nothing" -}}
{{- end -}}

{{- $peerKeys := keys .Values.ipsec.peers | sortAlpha -}}
{{- $carried := list -}}
{{- $names := list -}}
{{- $ids := list -}}
{{- range $child, $conn := .Values.ipsec.connections -}}
  {{- $ifName := include "ocudu-du.ipsec.ifName" (dict "name" $child "conn" $conn) -}}
  {{- if gt (len $ifName) 15 -}}
  {{- fail (printf "ipsec.connections.%s.ifName is %q, which is longer than the 15 characters an interface name can hold" $child $ifName) -}}
  {{- end -}}
  {{- if has $ifName $names -}}
  {{- fail (printf "ipsec.connections.%s.ifName is %q, and another connection already uses that name" $child $ifName) -}}
  {{- end -}}
  {{- $names = append $names $ifName -}}
  {{- $id := int (include "ocudu-du.ipsec.ifId" (dict "name" $child "conn" $conn)) -}}
  {{- if eq $id 0 -}}
  {{- fail (printf "ipsec.connections.%s.ifId is 0, and interface id 0 selects no tunnel at all" $child) -}}
  {{- end -}}
  {{- if has $id $ids -}}
  {{- fail (printf "ipsec.connections.%s.ifId is %d, and another connection already uses that id, so the two would share one tunnel" $child $id) -}}
  {{- end -}}
  {{- $ids = append $ids $id -}}
  {{- if not $conn.local -}}
  {{- fail (printf "ipsec.connections.%s.local is required: it is the protected address this pod binds to" $child) -}}
  {{- end -}}
  {{- if and $conn.protocol (not (has (toString $conn.protocol) (list "sctp" "udp" "tcp"))) -}}
  {{- fail (printf "ipsec.connections.%s.protocol is %q, and the only values are \"sctp\", \"udp\" and \"tcp\". Leave it out to admit any protocol between the two protected addresses" $child $conn.protocol) -}}
  {{- end -}}
  {{- if and (hasKey $conn "replayWindow") (eq (int $conn.replayWindow) 0) -}}
  {{- fail (printf "ipsec.connections.%s.replayWindow is 0, which switches replay protection off for that interface" $child) -}}
  {{- end -}}
  {{- if not $conn.remote -}}
  {{- fail (printf "ipsec.connections.%s.remote is required: it is the peer's protected address" $child) -}}
  {{- end -}}
  {{/*
  Which association carries this interface. With one peer there is nothing to choose, so
  the key may be left out. With two there is, and guessing would silently put an interface
  on the wrong association, where the peer identity checked is not the one that owns it.
  */}}
  {{- $peerName := "" -}}
  {{- if $conn.peer -}}
    {{- $peerName = toString $conn.peer -}}
  {{- else if eq (len $peerKeys) 1 -}}
    {{- $peerName = first $peerKeys -}}
  {{- else -}}
    {{- fail (printf "ipsec.connections.%s.peer is required: there is more than one entry in ipsec.peers, so which association carries this interface cannot be guessed" $child) -}}
  {{- end -}}
  {{- if not (has $peerName $peerKeys) -}}
  {{- fail (printf "ipsec.connections.%s.peer is %q, and ipsec.peers has no entry by that name" $child $peerName) -}}
  {{- end -}}
  {{- $carried = append $carried $peerName -}}
{{- end -}}

{{/*
A peer nothing names would render an association that protects no traffic. The daemon
would establish it, the readiness probe would see an established association, and the
interface it was meant to protect would be somewhere else entirely, in clear.
*/}}
{{- range $peerName, $peer := .Values.ipsec.peers -}}
{{- if not (has $peerName $carried) -}}
{{- fail (printf "ipsec.peers.%s carries no connection: the daemon would hold an association that protects nothing, and report itself ready for it" $peerName) -}}
{{- end -}}
{{- end -}}

{{- $blob := include "ocudu-du.ipsec.configBlob" . -}}
{{- $f1 := "" -}}
{{- range $key := (list "f1ap" "f1u") -}}
{{- $f1 = printf "%s\n%s" $f1 (include "ocudu-du.ipsec.section" (dict "blob" $blob "key" $key)) -}}
{{- end -}}
{{/*
Every address the protected sections name has to be one this chart knows about. A wildcard
leaves the application listening on the pod address as well, and a service name sends it
straight out of the tunnel. Both look like a working configuration and neither is protected.
*/}}
{{- $allowed := list "auto" -}}
{{- range $child, $conn := .Values.ipsec.connections -}}
{{- $allowed = append $allowed (toString $conn.local) -}}
{{- $allowed = append $allowed (toString $conn.remote) -}}
{{- end -}}
{{- $addrKeys := list "addr" "addrs" "bind_addr" "bind_addrs" "ext_addr" "ext_bind_addr" -}}
{{- range $line := splitList "\n" $f1 -}}
{{- $parts := splitn ":" 2 $line -}}
{{- $k := trimPrefix "- " (trim $parts._0) -}}
{{- $v := trimAll "\"'" (trim (default "" $parts._1)) -}}
{{- if and (has $k $addrKeys) (ne $v "") (not (has $v $allowed)) -}}
{{- if or (eq $v "0.0.0.0") (eq $v "::") -}}
{{- fail (printf "the application config still binds a protected interface to the wildcard address %s. With IPsec on, the application listens on the pod address as well as the protected one, so the tunnel can be walked around. Bind it to its address from ipsec.connections instead" $v) -}}
{{- end -}}
{{- fail (printf "the application config points a protected interface at %q, which is not one of the addresses in ipsec.connections. Traffic to or from it would not enter the tunnel" $v) -}}
{{- end -}}
{{- end -}}
{{- range $child, $conn := .Values.ipsec.connections -}}
{{- if not (contains $conn.local $f1) -}}
{{- fail (printf "ipsec.connections.%s.local is %s, and no protected section of the application config mentions it. The application would keep its old addresses and its traffic would not enter the tunnel" $child $conn.local) -}}
{{- end -}}
{{- end -}}

{{/*
F1-U must not sit on the port the policy has to leave open for the core.

The policy allows GTP-U to the core on UDP 2152 for N3, and a NetworkPolicy rule names a
port and an address range, never a peer. The peer's pod address is inside that range, so
while F1-U uses the same port that one rule also permits plaintext F1-U straight to the
peer, around the tunnel. The core's port is fixed in the application and cannot move;
F1-U's is configurable, so F1-U is what moves.

An absent bind_port is the same as 2152, because that is what the application defaults to.
*/}}
{{- $corePort := 2152 -}}
{{- $f1uPort := $corePort -}}
{{- $f1uSection := include "ocudu-du.ipsec.section" (dict "blob" $blob "key" "f1u") -}}
{{- range $line := splitList "\n" $f1uSection -}}
  {{- $parts := splitn ":" 2 $line -}}
  {{- if eq (trimPrefix "- " (trim $parts._0)) "bind_port" -}}
    {{- $f1uPort = int (trimAll "\"'" (trim (default "" $parts._1))) -}}
  {{- end -}}
{{- end -}}
{{- if and (eq $f1uPort $corePort) (not .Values.ipsec.allowF1uOnCorePort) -}}
{{- fail (printf "the application config leaves F1-U on UDP %d, which is the port the policy has to open for the core. That one rule then also permits plaintext F1-U to the peer's pod address, around the tunnel. Set f1u.bind_port to another port on both ends, or set ipsec.allowF1uOnCorePort to true if there is no core to reach" $corePort) -}}
{{- end -}}

{{- end -}}
{{- end -}}

{{/*
The tunnel interface for a connection. Defaults to `ipsec-<name>`, which is what it always
was in practice, so it is only worth setting where a specific name is required.

Call with: dict "name" <string> "conn" <map>
*/}}
{{- define "ocudu-du.ipsec.ifName" -}}
{{- default (printf "ipsec-%s" .name) .conn.ifName -}}
{{- end -}}

{{/*
The interface id for a connection. Purely local — nothing about it is negotiated or sent —
so the two ends need not agree on it and there is nothing to coordinate. Derived from the
connection name so it is stable across renders and unique without anyone counting. The
uniqueness guard still runs, because an override can collide with a derived one.

Call with: dict "name" <string> "conn" <map>
*/}}
{{- define "ocudu-du.ipsec.ifId" -}}
{{- if .conn.ifId -}}
{{- .conn.ifId -}}
{{- else -}}
{{- add (mod (int (adler32sum .name)) 65535) 1 -}}
{{- end -}}
{{- end -}}

{{/*
The peer that carries a connection. With exactly one peer the key may be left out, which
keeps a single-peer deployment reading the way it always did. The validation helper
refuses to render the moment that shortcut becomes ambiguous.
*/}}
{{- define "ocudu-du.ipsec.peerOf" -}}
{{- if .conn.peer -}}
{{- toString .conn.peer -}}
{{- else -}}
{{- first (keys .peers | sortAlpha) -}}
{{- end -}}
{{- end -}}

{{/*
The sidecar's security context, with NET_BIND_SERVICE removed when IKE no longer binds a
privileged port. The capability is only there for that bind: the socket plugin refuses to
open a privileged port without it however permissive the runtime is, and needs nothing once
the port is not privileged.
*/}}
{{- define "ocudu-du.ipsec.securityContext" -}}
{{- $ctx := deepCopy .Values.ipsec.securityContext -}}
{{- if .Values.ipsec.ikeOnNatTPortOnly -}}
{{- $_ := set $ctx.capabilities "add" (without $ctx.capabilities.add "NET_BIND_SERVICE") -}}
{{- end -}}
{{- toYaml $ctx -}}
{{- end -}}
