#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# GitLab is installed directly on the VM, so use its Rails runner.
# Monitoring endpoints only allow local clients by default.
curl -fsS --retry 120 --retry-delay 5 --retry-all-errors \
  --retry-max-time 600 --max-time 5 'http://127.0.0.1/-/readiness?all=1' >/dev/null

{
  printf "application = Base64.decode64('%s')\n" "$(base64 -w0 confs/application.yaml)"
  printf "seed = Base64.decode64('%s')\n" "$(base64 -w0 confs/manifests/deployment.yaml)"
  cat <<'RUBY'
source = YAML.safe_load(application).fetch('spec').fetch('source')
project_path = URI.parse(source.fetch('repoURL')).path.delete_prefix('/').delete_suffix('.git')
branch = source.fetch('targetRevision')
file_path = "#{source.fetch('path')}/deployment.yaml"

root = User.find_by_username!('root')
namespace, name = project_path.split('/')
abort('The bonus repository must be under root.') unless namespace == 'root'
project = Project.find_by_full_path(project_path)
unless project
  project = Projects::CreateService.new(root, {
    name: name, path: name, namespace_id: root.namespace_id,
    visibility_level: Gitlab::VisibilityLevel::PUBLIC
  }).execute
  abort("Project creation failed: #{project.errors.full_messages.join(', ')}") unless project.persisted?
end
abort("Existing #{project_path} must be public for Argo CD to read it.") unless project.public?

if project.empty_repo?
  result = Files::CreateService.new(project, root, {
    branch_name: branch, commit_message: 'Initialize playground manifests',
    file_path: file_path, file_content: seed
  }).execute
  abort("Initial commit failed: #{result[:message]}") unless result[:status] == :success
  puts "Created initial playground commit on #{branch}."
else
  abort("Existing repository needs #{file_path} on #{branch}; existing commits were preserved.") unless
    project.repository.blob_at(branch, file_path)
  puts 'Preserved existing playground repository and commits.'
end
puts "Repository ready: #{project.full_path}"
RUBY
} | sudo gitlab-rails runner -e production -
