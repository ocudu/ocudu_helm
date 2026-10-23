{{/*
SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
SPDX-License-Identifier: BSD-3-Clause-Open-MPI
*/}}

{{/*
Expand the name of the chart.
*/}}
{{- define "ocudu-cu.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "ocudu-cu.fullname" -}}
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
{{- define "ocudu-cu.mainConfigmapName" -}}
{{- with .Values.configmap }}
  {{- with .main }}
    {{- if .nameOverride }}
      {{- .nameOverride | trunc 63 | trimSuffix "-" -}}
    {{- else }}
      {{- printf "%s-config" (include "ocudu-cu.fullname" $) | trunc 63 | trimSuffix "-" -}}
    {{- end }}
  {{- else }}
    {{- printf "%s-config" (include "ocudu-cu.fullname" $) | trunc 63 | trimSuffix "-" -}}
  {{- end }}
{{- else }}
  {{- printf "%s-config" (include "ocudu-cu.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end }}
{{- end }}

{{/*
O1 mode configmap (values.o1Config)
*/}}
{{- define "ocudu-cu.o1ConfigmapName" -}}
{{- with .Values.configmap }}
  {{- with .o1 }}
    {{- if .nameOverride }}
      {{- .nameOverride | trunc 63 | trimSuffix "-" -}}
    {{- else }}
      {{- printf "%s-o1-config" (include "ocudu-cu.fullname" $) | trunc 63 | trimSuffix "-" -}}
    {{- end }}
  {{- else }}
    {{- printf "%s-o1-config" (include "ocudu-cu.fullname" $) | trunc 63 | trimSuffix "-" -}}
  {{- end }}
{{- else }}
  {{- printf "%s-o1-config" (include "ocudu-cu.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end }}
{{- end }}

{{/*
Entrypoint script configmap
*/}}
{{- define "ocudu-cu.entrypointConfigmapName" -}}
{{- with .Values.configmap }}
  {{- with .entrypoint }}
    {{- if .nameOverride }}
      {{- .nameOverride | trunc 63 | trimSuffix "-" -}}
    {{- else }}
      {{- printf "%s-entrypoint" (include "ocudu-cu.fullname" $) | trunc 63 | trimSuffix "-" -}}
    {{- end }}
  {{- else }}
    {{- printf "%s-entrypoint" (include "ocudu-cu.fullname" $) | trunc 63 | trimSuffix "-" -}}
  {{- end }}
{{- else }}
  {{- printf "%s-entrypoint" (include "ocudu-cu.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "ocudu-cu.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "ocudu-cu.labels" -}}
helm.sh/chart: {{ include "ocudu-cu.chart" . }}
{{ include "ocudu-cu.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "ocudu-cu.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ocudu-cu.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "ocudu-cu.serviceAccountName" -}}
{{- include "ocudu-cu.fullname" . }}
{{- end }}

{{/*
Create the image path
*/}}
{{- define "ocudu-cu.image" -}}
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
{{- define "ocudu-cu.mainImage" -}}
{{- $image := dict "repository" .Values.image.repository "tag" (default .Chart.AppVersion .Values.image.tag) -}}
{{- include "ocudu-cu.image" $image -}}
{{- end -}}

{{/*
Create the image path for the passed in image field of netconf-server image
*/}}
{{- define "ocudu-cu.o1.netconfServer.image" -}}
{{- if eq (substr 0 7 (.tag | toString)) "sha256:" -}}
{{- printf "%s@%s" .repository (.tag | toString) -}}
{{- else -}}
{{- printf "%s:%s" .repository (.tag | toString) -}}
{{- end -}}
{{- end -}}

{{/*
Create the image path for the passed in image field of o1-adapter image
*/}}
{{- define "ocudu-cu.o1.o1Adapter.image" -}}
{{- if eq (substr 0 7 (.tag | toString)) "sha256:" -}}
{{- printf "%s@%s" .repository (.tag | toString) -}}
{{- else -}}
{{- printf "%s:%s" .repository (.tag | toString) -}}
{{- end -}}
{{- end -}}

{{/*
Fail unless resources.requests and resources.limits both set cpu and memory.
*/}}
{{- define "ocudu-cu.requireResources" -}}
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
{{- define "ocudu-cu.ipsec.serviceName" -}}
{{- printf "%s-ipsec" (include "ocudu-cu.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Name of the configmap holding the IPsec configuration.
*/}}
{{- define "ocudu-cu.ipsec.configmapName" -}}
{{- printf "%s-ipsec-config" (include "ocudu-cu.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Sidecar image reference.
*/}}
{{- define "ocudu-cu.ipsec.image" -}}
{{- include "ocudu-cu.image" .Values.ipsec.image -}}
{{- end -}}

{{/*
Every application config document joined into one string, so it can be searched.
*/}}
{{- define "ocudu-cu.ipsec.configBlob" -}}
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
{{- define "ocudu-cu.ipsec.section" -}}
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
{{- define "ocudu-cu.ipsec.validate" -}}
{{- if and .Values.ipsec.protectN2 (not .Values.ipsec.enabled) -}}
{{- fail "ipsec.protectN2 needs ipsec.enabled to be true: without the sidecar there is no tunnel to carry N2, and N2 would stay in clear" -}}
{{- end -}}
{{- if and .Values.ipsec.protectN3 (not .Values.ipsec.enabled) -}}
{{- fail "ipsec.protectN3 needs ipsec.enabled to be true: without the sidecar there is no tunnel to carry N3, and N3 would stay in clear" -}}
{{- end -}}
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
{{- if and .Values.ipsec.protectN2 .Values.n2Service.enabled -}}
{{- fail "ipsec.protectN2 needs n2Service.enabled to be false: that service publishes an unprotected path to the N2 port on the pod address, which is the bypass this feature exists to close" -}}
{{- end -}}
{{- if and .Values.ipsec.protectN3 .Values.n3Service.enabled -}}
{{- fail "ipsec.protectN3 needs n3Service.enabled to be false: that service publishes an unprotected path to the N3 port on the pod address, which is the bypass this feature exists to close" -}}
{{- end -}}
{{- if and .Values.ipsec.protectN3 .Values.n3Service.advertisedAddress -}}
{{- fail "ipsec.protectN3 needs n3Service.advertisedAddress to be empty: N3 is advertised on its protected address, so the advertised address would be ignored" -}}
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
{{/*
A window wider than 32 needs extended sequence numbers. Without them the kernel cannot hold
a bitmap that size and ends up with a window of 1 — narrower than the 32 it would have used
had nobody asked for anything. The configuration loads either way and nothing reports it,
so this is refused at render time rather than discovered on a capture.
*/}}
{{- if gt (int .Values.ipsec.ike.replayWindow) 32 -}}
{{- $esp := .Values.ipsec.ike.espProposal -}}
{{- range $child, $conn := .Values.ipsec.connections -}}
{{- $esp = printf "%s %s" $esp (toString ($conn.espProposal | default "")) -}}
{{- end -}}
{{- if not (contains "esn" $esp) -}}
{{- fail (printf "ipsec.ike.replayWindow is %d, and a window wider than 32 needs extended sequence numbers: add esn to espProposal, or the kernel silently falls back to a window of 1" (int .Values.ipsec.ike.replayWindow)) -}}
{{- end -}}
{{- end -}}
{{- if not .Values.ipsec.connections -}}
{{- fail "ipsec.connections is empty: the sidecar would run and protect nothing" -}}
{{- end -}}

{{- $peerKeys := keys .Values.ipsec.peers | sortAlpha -}}
{{- $carried := list -}}
{{- $names := list -}}
{{- $ids := list -}}
{{- range $child, $conn := .Values.ipsec.connections -}}
  {{- $ifName := include "ocudu-cu.ipsec.ifName" (dict "name" $child "conn" $conn) -}}
  {{- if gt (len $ifName) 15 -}}
  {{- fail (printf "ipsec.connections.%s.ifName is %q, which is longer than the 15 characters an interface name can hold" $child $ifName) -}}
  {{- end -}}
  {{- if has $ifName $names -}}
  {{- fail (printf "ipsec.connections.%s.ifName is %q, and another connection already uses that name" $child $ifName) -}}
  {{- end -}}
  {{- $names = append $names $ifName -}}
  {{- $id := int (include "ocudu-cu.ipsec.ifId" (dict "name" $child "conn" $conn)) -}}
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
  {{- if hasKey $conn "replayWindow" -}}
  {{- fail (printf "ipsec.connections.%s.replayWindow is set, and the replay window is not a per-connection setting: the daemon takes one width for all of them. Set ipsec.ike.replayWindow instead" $child) -}}
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

{{- $blob := include "ocudu-cu.ipsec.configBlob" . -}}
{{- $sections := list "f1ap" "f1u" "xnap" "xnu" -}}
{{- if .Values.ipsec.protectN2 -}}
{{- $sections = concat $sections (list "amf" "extra_amfs") -}}
{{/*
The entrypoint no longer supplies an N2 bind address, so one has to be here, for the AMF and
for every extra AMF. Without it the application binds its default of 127.0.0.1, and N2 to
that AMF never comes up.
*/}}
{{- if not (regexMatch "(?m)^(- )?bind_addrs?:" (include "ocudu-cu.ipsec.section" (dict "blob" $blob "key" "amf"))) -}}
{{- fail "ipsec.protectN2 needs cu_cp.amf.bind_addrs: the entrypoint no longer binds N2 to the pod address, so without it the application binds 127.0.0.1 and N2 never comes up" -}}
{{- end -}}
{{- range $name, $doc := .Values.config -}}
{{- range $amf := dig "cu_cp" "extra_amfs" list (fromYaml (toString $doc)) -}}
{{- if not (or (hasKey $amf "bind_addrs") (hasKey $amf "bind_addr")) -}}
{{- fail (printf "ipsec.protectN2 needs bind_addrs in every entry of cu_cp.extra_amfs, and the one for %v has none: the application would bind 127.0.0.1 and N2 to that AMF would never come up" (default "an unnamed AMF" $amf.addrs)) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- if .Values.ipsec.protectN3 -}}
{{- $sections = append $sections "ngu" -}}
{{/*
The same for N3. Without a bind address the application binds its default of 127.0.0.1, and
N3 never comes up.
*/}}
{{- if not (regexMatch "(?m)^(- )?bind_addr:" (include "ocudu-cu.ipsec.section" (dict "blob" $blob "key" "ngu"))) -}}
{{- fail "ipsec.protectN3 needs cu_up.ngu.socket[].bind_addr: the entrypoint no longer binds N3 to the pod address, so without it the application binds 127.0.0.1 and N3 never comes up" -}}
{{- end -}}
{{- end -}}
{{- $protected := "" -}}
{{- range $key := $sections -}}
{{- $protected = printf "%s\n%s" $protected (include "ocudu-cu.ipsec.section" (dict "blob" $blob "key" $key)) -}}
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
{{- $addrKeys := list "addr" "addrs" "bind_addr" "bind_addrs" "ext_addr" "ext_bind_addr" "peer_addrs" -}}
{{/*
Every one of these keys takes a list as readily as a scalar, and a list writes its values on
their own lines with no key beside them. Reading the key alone would see `bind_addrs:` with
nothing after it, then a bare `- 0.0.0.0` that looks like no address at all, and let both
through. So a line that is only a list item is measured against the key that opened the
list, and any other line closes it.
*/}}
{{- $pending := false -}}
{{- range $line := splitList "\n" $protected -}}
{{- $text := trim $line -}}
{{- $item := hasPrefix "- " $text -}}
{{- $body := trim (trimPrefix "- " $text) -}}
{{- $parts := splitn ":" 2 $body -}}
{{- $k := trim $parts._0 -}}
{{- $v := trimAll "\"'" (trim (default "" $parts._1)) -}}
{{- $addr := "" -}}
{{- if has $k $addrKeys -}}
  {{- $pending = true -}}
  {{- if ne $v "" -}}
    {{- $addr = $v -}}
    {{- $pending = false -}}
  {{- end -}}
{{- else if and $item $pending -}}
  {{- $addr = trimAll "\"'" $body -}}
{{- else -}}
  {{- $pending = false -}}
{{- end -}}
{{/*
A named device pins the socket to it, so the traffic leaves through that device rather than
the tunnel interface, whatever address it is bound to.
*/}}
{{- if and (eq $k "bind_interface") (ne $v "auto") -}}
{{- fail (printf "the application config binds a protected interface to the network device %q. The socket is pinned to that device, so its traffic leaves there instead of through the tunnel. Leave bind_interface at auto" $v) -}}
{{- end -}}
{{- if and (ne $addr "") (not (has $addr $allowed)) -}}
{{- if or (eq $addr "0.0.0.0") (eq $addr "::") -}}
{{- fail (printf "the application config still binds a protected interface to the wildcard address %s. With IPsec on, the application listens on the pod address as well as the protected one, so the tunnel can be walked around. Bind it to its address from ipsec.connections instead" $addr) -}}
{{- end -}}
{{- fail (printf "the application config points a protected interface at %q, which is not one of the addresses in ipsec.connections. Traffic to or from it would not enter the tunnel" $addr) -}}
{{- end -}}
{{- end -}}
{{- range $child, $conn := .Values.ipsec.connections -}}
{{- if not (contains $conn.local $protected) -}}
{{- fail (printf "ipsec.connections.%s.local is %s, and no protected section of the application config mentions it. The application would keep its old addresses and its traffic would not enter the tunnel" $child $conn.local) -}}
{{- end -}}
{{- end -}}

{{/*
A protected user-plane interface must not sit on the port the policy has to leave open for
the core.

The policy allows GTP-U to the core on UDP 2152 for N3, and a NetworkPolicy rule names a
port and an address range, never a peer. The peer's pod address is inside that range, so
while a protected interface uses that same port, the one rule opened for the core also
permits plaintext traffic straight to the peer, around the tunnel. The core's port is fixed
in the application and cannot move; F1-U's and Xn-U's are configurable, so they are what
move.

An absent bind_port is the same as 2152, because that is what the application defaults to.
A section the config does not carry at all is not checked, because that interface is not in
use.

With N3 protected the policy opens no plaintext port to the core, so there is nothing to
share and nothing to check.
*/}}
{{- if not .Values.ipsec.protectN3 -}}
{{- $corePort := 2152 -}}
{{- $planes := list
      (dict "key" "f1u" "name" "F1-U" "flag" "allowF1uOnCorePort" "allow" .Values.ipsec.allowF1uOnCorePort)
      (dict "key" "xnu" "name" "Xn-U" "flag" "allowXnuOnCorePort" "allow" .Values.ipsec.allowXnuOnCorePort) -}}
{{- range $plane := $planes -}}
{{- $section := include "ocudu-cu.ipsec.section" (dict "blob" $blob "key" $plane.key) -}}
{{- if ne (trim $section) "" -}}
{{- $port := $corePort -}}
{{- range $line := splitList "\n" $section -}}
  {{- $parts := splitn ":" 2 $line -}}
  {{- if eq (trimPrefix "- " (trim $parts._0)) "bind_port" -}}
    {{- $port = int (trimAll "\"'" (trim (default "" $parts._1))) -}}
  {{- end -}}
{{- end -}}
{{- if and (eq $port $corePort) (not $plane.allow) -}}
{{- fail (printf "the application config leaves %s on UDP %d, which is the port the policy has to open for the core. That one rule then also permits plaintext %s to the peer's pod address, around the tunnel. Set %s.bind_port to another port on both ends, or set ipsec.%s to true if there is no core to reach" $plane.name $corePort $plane.name $plane.key $plane.flag) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- end -}}
{{- end -}}

{{/*
The tunnel interface for a connection. Defaults to `ipsec-<name>`, which is what it always
was in practice, so it is only worth setting where a specific name is required.

Call with: dict "name" <string> "conn" <map>
*/}}
{{- define "ocudu-cu.ipsec.ifName" -}}
{{- default (printf "ipsec-%s" .name) .conn.ifName -}}
{{- end -}}

{{/*
The interface id for a connection. Purely local — nothing about it is negotiated or sent —
so the two ends need not agree on it and there is nothing to coordinate. Derived from the
connection name so it is stable across renders and unique without anyone counting. The
uniqueness guard still runs, because an override can collide with a derived one.

Call with: dict "name" <string> "conn" <map>
*/}}
{{- define "ocudu-cu.ipsec.ifId" -}}
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
{{- define "ocudu-cu.ipsec.peerOf" -}}
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
{{- define "ocudu-cu.ipsec.securityContext" -}}
{{- $ctx := deepCopy .Values.ipsec.securityContext -}}
{{- if .Values.ipsec.ikeOnNatTPortOnly -}}
{{- $_ := set $ctx.capabilities "add" (without $ctx.capabilities.add "NET_BIND_SERVICE") -}}
{{- end -}}
{{- toYaml $ctx -}}
{{- end -}}

{{/*
Name of the Secret holding the NETCONF SSH user's password (key "password").
Production: o1.netconfServer.ssh.passwordSecret (operator-managed Secret).
Dev/test: a chart-created Secret named after the release.
Fails rendering when o1.netconfServer.ssh.username is set but neither is.
*/}}
{{- define "ocudu-cu.netconfSshCredentialsSecretName" -}}
{{- $ssh := ((.Values.o1).netconfServer).ssh | default dict -}}
{{- if $ssh.passwordSecret -}}
{{- $ssh.passwordSecret -}}
{{- else if $ssh.password -}}
{{- printf "%s-netconf-ssh-credentials" (include "ocudu-cu.fullname" $) | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- fail "o1.netconfServer.ssh: set passwordSecret (existing Secret with key \"password\", production) or password (chart creates the Secret, dev/test) when username is set" -}}
{{- end -}}
{{- end }}
