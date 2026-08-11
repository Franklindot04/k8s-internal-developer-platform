#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'

runtime_path, feature_path = ARGV
abort 'usage: assert-golden-path-render.rb <runtime-render.yaml> <feature-render.yaml>' unless runtime_path && feature_path

def load_docs(path)
  YAML.load_stream(File.read(path)).compact
end

def find_doc(docs, kind, name)
  docs.find { |doc| doc['kind'] == kind && doc.dig('metadata', 'name') == name }
end

def assert(condition, message)
  abort "[error] #{message}" unless condition
end

runtime = load_docs(runtime_path)
feature = load_docs(feature_path)

name = 'golden-path-demo-golden-path'
deployment = find_doc(runtime, 'Deployment', name)
service = find_doc(runtime, 'Service', name)
service_account = find_doc(runtime, 'ServiceAccount', name)
configmap = find_doc(runtime, 'ConfigMap', "#{name}-config")
pdb = find_doc(runtime, 'PodDisruptionBudget', name)

assert(deployment, 'runtime Deployment is missing')
assert(service, 'runtime Service is missing')
assert(service_account, 'runtime ServiceAccount is missing')
assert(configmap, 'runtime ConfigMap is missing')
assert(pdb, 'runtime PodDisruptionBudget is missing')

selector = deployment.dig('spec', 'selector', 'matchLabels')
pod_labels = deployment.dig('spec', 'template', 'metadata', 'labels')
service_selector = service.dig('spec', 'selector')
assert(selector == service_selector, 'Service selector does not match Deployment selector')
assert(selector.all? { |key, value| pod_labels[key] == value }, 'Deployment selector is not present on pod template')

container = deployment.dig('spec', 'template', 'spec', 'containers').first
port = container['ports'].first
service_port = service.dig('spec', 'ports').first
assert(port['name'] == 'http', 'container port is not named http')
assert(port['containerPort'] == 8080, 'container port is not 8080')
assert(service_port['targetPort'] == 'http', 'Service targetPort does not use the named container port')

pod_security = deployment.dig('spec', 'template', 'spec', 'securityContext')
container_security = container['securityContext']
assert(pod_security['runAsNonRoot'] == true, 'pod runAsNonRoot is not true')
assert(pod_security.dig('seccompProfile', 'type') == 'RuntimeDefault', 'pod seccompProfile is not RuntimeDefault')
assert(container_security['allowPrivilegeEscalation'] == false, 'container allows privilege escalation')
assert(container_security['readOnlyRootFilesystem'] == true, 'container filesystem is not read-only')
assert(container_security['runAsNonRoot'] == true, 'container runAsNonRoot is not true')
assert(container_security.dig('capabilities', 'drop').include?('ALL'), 'container does not drop all capabilities')

resources = container['resources']
assert(resources.dig('requests', 'cpu'), 'CPU request is missing')
assert(resources.dig('requests', 'memory'), 'memory request is missing')
assert(resources.dig('limits', 'cpu'), 'CPU limit is missing')
assert(resources.dig('limits', 'memory'), 'memory limit is missing')

image = container['image']
assert(image.include?('@sha256:'), 'runtime image is not digest-pinned')
assert(!image.include?(':latest'), 'runtime image uses latest')
assert(runtime.none? { |doc| doc['kind'] == 'Secret' }, 'chart rendered a Secret resource')
assert(runtime.none? { |doc| doc['kind'] == 'HorizontalPodAutoscaler' }, 'runtime profile rendered HPA unexpectedly')
assert(runtime.none? { |doc| doc['kind'] == 'Ingress' }, 'runtime profile rendered Ingress unexpectedly')
assert(runtime.none? { |doc| doc['kind'] == 'NetworkPolicy' }, 'runtime profile rendered NetworkPolicy unexpectedly')

assert(deployment.dig('spec', 'template', 'metadata', 'annotations', 'checksum/config').to_s.match?(/[a-f0-9]{64}/), 'ConfigMap checksum annotation is missing')

feature_kinds = feature.map { |doc| doc['kind'] }
assert(feature_kinds.include?('HorizontalPodAutoscaler'), 'feature profile did not render HPA')
assert(feature_kinds.include?('Ingress'), 'feature profile did not render Ingress')
assert(feature_kinds.include?('NetworkPolicy'), 'feature profile did not render NetworkPolicy')
assert(feature.none? { |doc| doc['kind'] == 'Secret' }, 'feature profile rendered a Secret resource')

puts '[ok] golden-path rendered contract assertions passed'
