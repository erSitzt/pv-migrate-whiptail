# Simple shell UI using whiptail to migrate volumes in kubernetes clusters to a new storage class

Needs
 - kubectl with pv-migrate installed
 - yq
 - whiptail

TLDR What it does:
 - Select a deployment type (StatefulSet/Deployment)
 - Select a namespace
 - Select the workload
 - Select the label to find the assiciated pods by
 - Select the new storage class
 - Select the pod/first pod to migrate the associated volume
 - Scale down the workload
 - Dump the original pvc/pv yaml in a directory stucture ./NAMESPACE/WORKLOAD_NAME/original
 - Create new pvc in ./NAMESPACE/WORKLOAD_NAME/modified
 - Modify and apply new pvc with new storage class
 - use pv-migrate to rsync/copy data from old pv to new pv
 - remap pv/pvc to the newly provisioned pv
 - delete old pv
 - continue with additional pods (in case of a statefulset)

This was created to help me migrate data with minimal impact after changing the storage class in our clusters.
This might not do what you need, but it might be a starting point.
It wont win any beauty contests...

