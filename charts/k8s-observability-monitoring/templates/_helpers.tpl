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
