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
(per-collector overrides + spiffe-helper when listed in spiffe.collectors; Task 6 adds Hubble),
then concatenating their list-valued extras. Emits an "alloy:\n  <merged>" block, or nothing.
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
{{- /* TASK 6 INSERTS THE HUBBLE FRAGMENT APPEND HERE */ -}}
{{- if gt (len $frags) 0 -}}
  {{- $merged := include "k8s-monitoring.mergeAlloyFragments" $frags | fromYaml -}}
{{ toYaml $merged }}
{{- end -}}
{{- end }}
