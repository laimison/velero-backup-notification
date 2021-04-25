# velero-backup-notification

This is a simple Kubernetes controller written in Ruby that sends email and/or Slack notifications when backups or restores are performed by [Velero](https://velero.io/).

## Installation

- Clone the repo
- Install with Helm

```bash
helm install ./helm \
  --generate-name \
  --namespace velero \
  --set velero_namespace=velero \
  --set slack.enabled=true \
  --set slack.webhook=https://... \
  --set slack.channel=velero \
  --set slack.username=Velero \
  --set email.enabled=true \
  --set email.smtp.host=... \
  --set email.smtp.port=587 \
  --set email.smtp.username=... \
  --set email.smtp.password=... \
  --set email.from_address=... \
  --set email.to_address=... \
  --set email.from_sender_name="Company X" \
  --set email.subject_prefix="[development]"
```

That's it! You should now receive notifications when a backup/restore is started and when it's completed.

## Building Docker

```
cd velero-backup-notification

docker login --username=laimison
docker build -t velero-backup-notification .
docker images | head
docker tag mytag laimison/velero-backup-notification:latest
docker push laimison/velero-backup-notification:latest

docker tag mytag laimison/velero-backup-notification:0.1
docker push laimison/velero-backup-notification:0.1
```
