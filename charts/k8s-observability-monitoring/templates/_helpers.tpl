{{/*
Validate clusterName is set to a non-empty value.
Usage: {{ include "k8s-monitoring.validateClusterName" . }}
*/}}
{{- define "k8s-monitoring.validateClusterName" -}}
  {{- if not (or .Values.clusterName (ne .Values.clusterName "")) -}}
    {{- fail "clusterName must be set to a non-empty value at install time (e.g., --set clusterName=my-cluster)" -}}
  {{- end }}
{{- end }}

{{/*
Produce the Alloy values fragment that attaches the spiffe-helper sidecar to an upstream
collector, so it can authenticate to SPIFFE (bearerToken) destinations. Mirrors the sidecar
wiring used by custom-alloy. Reuses the <release>-custom-alloy-spiffe-helper ConfigMap.
Usage: {{ include "k8s-monitoring.spiffeCollectorValues" . }}  (pass the root context)
*/}}
{{- define "k8s-monitoring.spiffeCollectorValues" -}}
controller:
  initContainers:
    - name: spiffe-helper-init
      image: {{ .Values.spiffe.helper.image }}
      args: ["-config", "/etc/spiffe-helper/spiffe-helper.conf", "-daemon-mode=false"]
      resources:
        {{- toYaml .Values.spiffe.helper.resources | nindent 8 }}
      volumeMounts:
        - { name: spiffe-workload-api, mountPath: /spiffe-workload-api, readOnly: true }
        - { name: spiffe-helper-config, mountPath: /etc/spiffe-helper, readOnly: true }
        - { name: spiffe-jwt, mountPath: {{ dir .Values.spiffe.jwtPath | quote }} }
  extraContainers:
    - name: spiffe-helper
      image: {{ .Values.spiffe.helper.image }}
      args: ["-config", "/etc/spiffe-helper/spiffe-helper.conf"]
      resources:
        {{- toYaml .Values.spiffe.helper.resources | nindent 8 }}
      volumeMounts:
        - { name: spiffe-workload-api, mountPath: /spiffe-workload-api, readOnly: true }
        - { name: spiffe-helper-config, mountPath: /etc/spiffe-helper, readOnly: true }
        - { name: spiffe-jwt, mountPath: {{ dir .Values.spiffe.jwtPath | quote }} }
  volumes:
    extra:
      - { name: spiffe-workload-api, csi: { driver: csi.spiffe.io, readOnly: true } }
      - name: spiffe-helper-config
        configMap:
          name: {{ .Release.Name }}-custom-alloy-spiffe-helper
      - { name: spiffe-jwt, emptyDir: {} }
alloy:
  mounts:
    extra:
      - { name: spiffe-jwt, mountPath: {{ dir .Values.spiffe.jwtPath | quote }}, readOnly: true }
{{- end }}

{{/*
Concatenate the list-valued "extra" keys (controller.volumes.extra and alloy.mounts.extra)
across a list of Alloy-values fragments, returning a single merged dict. mergeOverwrite REPLACES
lists, so we must concat these explicitly. Input: a list of dicts. Output: merged dict.
Usage: {{ include "k8s-monitoring.mergeAlloyFragments" (list $frag1 $frag2) | fromYaml ... }}
*/}}
{{- define "k8s-monitoring.mergeAlloyFragments" -}}
{{- $merged := dict -}}
{{- $vols := list -}}
{{- $mounts := list -}}
{{- range . -}}
  {{- $f := deepCopy . -}}
  {{- $vols = concat $vols (dig "controller" "volumes" "extra" (list) $f) -}}
  {{- $mounts = concat $mounts (dig "alloy" "mounts" "extra" (list) $f) -}}
  {{- $merged = mergeOverwrite $merged $f -}}
{{- end -}}
{{- if gt (len $vols) 0 -}}
  {{- $_ := set $merged "controller" (mergeOverwrite (dig "controller" (dict) $merged) (dict "volumes" (dict "extra" $vols))) -}}
{{- end -}}
{{- if gt (len $mounts) 0 -}}
  {{- $_ := set $merged "alloy" (mergeOverwrite (dig "alloy" (dict) $merged) (dict "mounts" (dict "extra" $mounts))) -}}
{{- end -}}
{{- toYaml $merged -}}
{{- end }}

{{/*
Compute the merged Alloy values for a named upstream collector by collecting fragments
(per-collector overrides + spiffe-helper when listed in spiffe.collectors + Hubble on alloy-logs),
then concatenating their list-valued extras. Emits the merged collector values (top-level
controller/alloy/etc. keys) for use under the collector name, or nothing if no fragments apply.
Usage: {{ include "k8s-monitoring.collectorAlloyBlock" (dict "ctx" . "name" "alloy-logs") }}
*/}}
{{- define "k8s-monitoring.collectorAlloyBlock" -}}
{{- $ctx := .ctx -}}
{{- $name := .name -}}
{{- $frags := list -}}
{{- $override := index $ctx.Values.collectors $name -}}
{{- if $override -}}
  {{- $frags = append $frags (deepCopy $override) -}}
{{- end -}}
{{- if and $ctx.Values.spiffe.enabled (has $name $ctx.Values.spiffe.collectors) -}}
  {{- $frags = append $frags (include "k8s-monitoring.spiffeCollectorValues" $ctx | fromYaml) -}}
{{- end -}}
{{- if and (eq $name "alloy-logs") $ctx.Values.hubbleFlowLogs.enabled -}}
  {{- $frags = append $frags (include "k8s-monitoring.hubbleMountValues" $ctx | fromYaml) -}}
{{- end -}}
{{- if gt (len $frags) 0 -}}
  {{- $merged := include "k8s-monitoring.mergeAlloyFragments" $frags | fromYaml -}}
{{ toYaml $merged }}
{{- end -}}
{{- end }}

{{/*
Resolve the list of destination NAMES that Hubble flows should be shipped to.
hubbleFlowLogs.destinations if non-empty, else podLogsViaLoki.destinations if non-empty,
else all destinations whose logs.enabled is true.
Usage: {{ include "k8s-monitoring.hubbleDestinations" . }}  -> space-separated names
*/}}
{{- define "k8s-monitoring.hubbleDestinations" -}}
{{- $names := list -}}
{{- if gt (len .Values.hubbleFlowLogs.destinations) 0 -}}
  {{- $names = .Values.hubbleFlowLogs.destinations -}}
{{- else if gt (len .Values.podLogsViaLoki.destinations) 0 -}}
  {{- $names = .Values.podLogsViaLoki.destinations -}}
{{- else -}}
  {{- range $name, $dest := .Values.destinations -}}
    {{- if and (hasKey $dest "logs") $dest.logs.enabled -}}
      {{- $names = append $names $name -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- $names | join " " -}}
{{- end }}

{{/*
Render the Alloy extraConfig sub-pipeline that tails the Hubble export file and ships flows to
each resolved destination's OTLP exporter, with its own small batch. Returns a raw Alloy
config string (to be placed under collectors.alloy-logs.alloy.extraConfig).
Usage: {{ include "k8s-monitoring.hubbleExtraConfig" . }}
*/}}
{{- define "k8s-monitoring.hubbleExtraConfig" -}}
{{- $ctx := . -}}
{{- $destNames := splitList " " (include "k8s-monitoring.hubbleDestinations" .) -}}
{{- $exporters := list -}}
{{- range $destNames -}}
  {{- if . -}}
    {{- $san := . | lower | replace " " "_" | replace "-" "_" -}}
    {{- $dest := index $ctx.Values.destinations . -}}
    {{- if and $dest (eq (dig "protocol" "http" $dest) "grpc") -}}
      {{- $exporters = append $exporters (printf "otelcol.exporter.otlp.%s.input" $san) -}}
    {{- else -}}
      {{- $exporters = append $exporters (printf "otelcol.exporter.otlphttp.%s.input" $san) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
local.file_match "hubble" {
  path_targets = [{
    __path__ = {{ .Values.hubbleFlowLogs.exportFilePath | quote }},
    job      = "cilium/hubble-flows",
  }]
}
loki.source.file "hubble" {
  targets    = local.file_match.hubble.targets
  forward_to = [loki.process.hubble.receiver]
}
loki.process "hubble" {
  stage.json {
    expressions = {
      verdict   = "flow.verdict",
      flow_type = "flow.Type",
      src_ns    = "flow.source.namespace",
      dst_ns    = "flow.destination.namespace",
    }
  }
  stage.structured_metadata {
    values = { verdict = "", flow_type = "", src_ns = "", dst_ns = "" }
  }
  forward_to = [otelcol.receiver.loki.hubble.receiver]
}
otelcol.receiver.loki "hubble" {
  output { logs = [otelcol.processor.transform.hubble.input] }
}
otelcol.processor.transform "hubble" {
  error_mode = "ignore"
  log_statements {
    context = "resource"
    statements = [
      `set(attributes["service.name"], "hubble-flows")`,
      `set(attributes["service.namespace"], "cilium")`,
      `set(attributes["k8s.cluster.name"], {{ .Values.clusterName | quote }})`,
    ]
  }
  output { logs = [otelcol.processor.batch.hubble.input] }
}
otelcol.processor.batch "hubble" {
  timeout             = "2s"
  send_batch_size     = {{ .Values.hubbleFlowLogs.batchMaxSize }}
  send_batch_max_size = {{ .Values.hubbleFlowLogs.batchMaxSize }}
  output {
    logs = [{{ $exporters | join ", " }}]
  }
}
{{- end }}

{{/*
Alloy values fragment giving alloy-logs a read-only hostPath mount of the Hubble export dir.
Usage: {{ include "k8s-monitoring.hubbleMountValues" . }}
*/}}
{{- define "k8s-monitoring.hubbleMountValues" -}}
{{- $dir := dir .Values.hubbleFlowLogs.exportFilePath -}}
controller:
  volumes:
    extra:
      - name: hubble-export
        hostPath:
          path: {{ $dir | quote }}
          type: Directory
alloy:
  extraConfig: |-
{{ include "k8s-monitoring.hubbleExtraConfig" . | indent 4 }}
  mounts:
    extra:
      - name: hubble-export
        mountPath: {{ $dir | quote }}
        readOnly: true
{{- end }}

{{/*
Validate Hubble flow-log configuration.
Usage: {{ include "k8s-monitoring.validateHubbleFlowLogs" . }}
*/}}
{{- define "k8s-monitoring.validateHubbleFlowLogs" -}}
{{- if .Values.hubbleFlowLogs.enabled -}}
  {{- $destNames := splitList " " (include "k8s-monitoring.hubbleDestinations" .) -}}
  {{- if or (eq (len $destNames) 0) (eq (join "" $destNames) "") -}}
    {{- fail "hubbleFlowLogs.enabled is true but no logs-enabled destination could be resolved. Set hubbleFlowLogs.destinations, or podLogsViaLoki.destinations, or enable logs on a destination." -}}
  {{- end -}}
  {{- range $destNames -}}
    {{- $dest := index $.Values.destinations . -}}
    {{- if and $dest $dest.auth (eq (dig "auth" "type" "" $dest) "bearerToken") -}}
      {{- if not (and $.Values.spiffe.enabled (has "alloy-logs" $.Values.spiffe.collectors)) -}}
        {{- fail (printf "hubbleFlowLogs targets destination %q which uses SPIFFE bearerToken auth, but alloy-logs has no spiffe-helper sidecar. Add \"alloy-logs\" to spiffe.collectors (and set spiffe.enabled=true), otherwise the alloy-logs DaemonSet will crash-loop with a missing token file." .) -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end }}
