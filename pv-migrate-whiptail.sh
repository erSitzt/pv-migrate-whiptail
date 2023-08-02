#!/bin/bash

# Select Deployment/Workload Type
OPTION=$(whiptail --title "Menu Dialog" --menu "Choose your option" 15 60 4 \
"1" "Deployment" \
"2" "StatefulSet"  3>&1 1>&2 2>&3)

exitstatus=$?
if [ $exitstatus = 0 ]; then
    echo "Your chosen option: $OPTION"
    if [ $OPTION = "1" ]; then
        type="deployments"
    elif [ $OPTION = "2" ]; then
        type="statefulsets"
    fi
elif [ $exitstatus = 255 ]; then
    echo "ESC pressed. Exiting."
    exit 1
else
    echo "You chose Cancel."
fi

# Select the namespace
namespaces=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}')
NAMESPACE=$(whiptail --title "Select Namespace" --menu "Choose your option" 25 60 15 $(echo $namespaces | tr ' ' '\n' | nl -w1 -s ' ') 3>&1 1>&2 2>&3)
exitstatus=$?
if [ $exitstatus = 1 ] || [ $exitstatus = 255 ]; then
    echo "User selected No, exit the script"
    exit 1
fi
NAMESPACE=$(echo $namespaces | tr ' ' '\n' | sed -n "${NAMESPACE}p")
# debug
# echo $NAMESPACE

# Select Workload
workloads=$(kubectl get $type -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}')
echo $workloads
# check if at least one statefulset/deployment was found/selected
if [ -n "$workloads" ]; then
    WORKLOAD_NAME=$(whiptail --title "Select Statefulset" --menu "Choose your option" 25 60 15 $(echo $workloads | tr ' ' '\n' | nl -w1 -s ' ') 3>&1 1>&2 2>&3)
    exitstatus=$?
    if [ $exitstatus = 1 ] || [ $exitstatus = 255 ]; then
        echo "User selected No, exit the script"
        exit 1
    fi
    WORKLOAD_NAME=$(echo $workloads | tr ' ' '\n' | sed -n "${WORKLOAD_NAME}p")
    echo $WORKLOAD_NAME
fi

labels=$(kubectl get $type -n $NAMESPACE $WORKLOAD_NAME -o json | jq -r '.spec.template.metadata.labels | to_entries[] | "\(.key)=\(.value)"')
if [ -n "$workloads" ]; then
    LABEL_NAME=$(whiptail --title "Select Label to get Pods" --menu "Choose your option" 25 60 15 $(echo $labels | tr ' ' '\n' | nl -w1 -s ' ') 3>&1 1>&2 2>&3)
    exitstatus=$?
    if [ $exitstatus = 1 ] || [ $exitstatus = 255 ]; then
        echo "User selected No, exit the script"
        exit 1
    fi
    LABEL_NAME=$(echo $labels | tr ' ' '\n' | sed -n "${LABEL_NAME}p")
    echo $LABEL_NAME
fi


storageclasses=$(kubectl get storageclass -o jsonpath='{.items[*].metadata.name}')
NEW_STORAGE_CLASS=$(whiptail --title "Select new StorageClass" --menu "Choose your option" 15 60 4 $(echo $storageclasses | tr ' ' '\n' | nl -w1 -s ' ') 3>&1 1>&2 2>&3)
exitstatus=$?
if [ $exitstatus = 1 ] || [ $exitstatus = 255 ]; then
    echo "User selected No, exit the script"
    exit 1
fi
NEW_STORAGE_CLASS=$(echo $storageclasses | tr ' ' '\n' | sed -n "${NEW_STORAGE_CLASS}p")
echo $NEW_STORAGE_CLASS


# Get the list of pods and PVCs before scaling down
declare -A pod_pvcs
for pod in $(kubectl get pods -n $NAMESPACE -l $LABEL_NAME -o jsonpath='{.items[*].metadata.name}')
do
  pod_pvcs["$pod"]=$(kubectl get pod -n $NAMESPACE $pod -o jsonpath='{.spec.volumes[*].persistentVolumeClaim.claimName}')
done

echo "Num pods found : ${#pod_pvcs[@]}"
if [ ${#pod_pvcs[@]} -eq 0 ]; then
    echo "No pods found with label : $LABEL_NAME"
    exit 1
fi

whiptail --yesno "Do you want to continue ?? This will scale $WORKLOAD_NAME down !!!" 10 60
status=$?
if [ $status = 1 ] || [ $status = 255 ]; then
    echo "User selected No, abort for $WORKLOAD_NAME"
    exit 1
fi
# Scale down the Workload
echo "Scaling down $type : $WORKLOAD_NAME"
kubectl scale $type/$WORKLOAD_NAME --namespace=$NAMESPACE --replicas=0

mkdir -p $NAMESPACE/$WORKLOAD_NAME/original
mkdir -p $NAMESPACE/$WORKLOAD_NAME/modified
for pod in "${!pod_pvcs[@]}"
do
  whiptail --yesno "Do you want to continue with POD $pod?" 10 60

  # check the exit status
  status=$?
  if [ $status = 1 ] || [ $status = 255 ]; then
      echo "User selected No, skip POD $pod"
      continue
  fi
  for pvc in ${pod_pvcs["$pod"]}
    do
        whiptail --yesno "Do you want to continue with pvc $pvc?" 10 60

        # check the exit status
        status=$?
        if [ $status = 1 ] || [ $status = 255 ]; then
            echo "User selected No, skip pvc $pvc"
            continue
        fi
        echo "Dumping Original YAML for PVC: $pvc"
        kubectl get pvc -n $NAMESPACE $pvc -o yaml | kubectl neat > $NAMESPACE/$WORKLOAD_NAME/original/$pvc.yaml
        pv=$(kubectl get pvc -n $NAMESPACE $pvc -o jsonpath='{.spec.volumeName}')
        echo "Dumping YAML for PV: $pv"
        kubectl get pv $pv -o yaml | kubectl neat > $NAMESPACE/$WORKLOAD_NAME/original/$pv.yaml
        echo "Dumping Modified YAML for PVC: $pvc with new StorageClass: $NEW_STORAGE_CLASS"
        kubectl get pvc -n $NAMESPACE $pvc -o yaml | kubectl neat | 
            /usr/bin/yq w - "metadata.name" "$pvc-new" | 
            /usr/bin/yq w - "spec.storageClassName" "$NEW_STORAGE_CLASS" | 
            /usr/bin/yq d - "metadata.annotations" | 
            /usr/bin/yq d - "spec.volumeName"  > $NAMESPACE/$WORKLOAD_NAME/modified/$pvc-new.yaml

        CURRENTFILE=$NAMESPACE/$WORKLOAD_NAME/modified/$pvc-new.yaml
        echo "Applying $CURRENTFILE"
        sleep 5
        kubectl apply -f $CURRENTFILE
        sleep 15
        pv_new=$(kubectl get pvc -n $NAMESPACE $pvc-new -o jsonpath='{.spec.volumeName}')
        echo "Patching new PV: $pv_new"
        kubectl patch pv $pv_new -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
        # Extract the name of the new PVC from the filename
        NEW_PVC_NAME=$(basename $CURRENTFILE .yaml)
        # Assume the old PVC name is the new one without '-new'
        OLD_PVC_NAME=${NEW_PVC_NAME%-new}
        echo "Migrating data from $OLD_PVC_NAME to $NEW_PVC_NAME"
        kubectl pv-migrate migrate --ignore-mounted -n $NAMESPACE -N $NAMESPACE $OLD_PVC_NAME $NEW_PVC_NAME
        echo "status"
        echo $?
        echo "status"

        # sleep to see result
        sleep 10
        
        ################################################################################
        #
        # From here on the PVCs/PCs will be modified / deleted and stuff..
        #
        ################################################################################
        whiptail --yesno "Do you want to continue? Original pvc/pv will be modified/deleted in the process" 10 60

        # check the exit status
        status=$?
        if [ $status = 1 ] || [ $status = 255 ]; then
            echo "User selected No, exit the script"
            exit 1
        fi

        echo "User selected Yes, continue the script"
        echo "Patching original PV: $pv"
        kubectl patch pv $pv -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
        echo "Deleting original PVC: $pvc"
        kubectl delete pvc -n $NAMESPACE $pvc
        echo "Deleting new PVC: $pvc-new"
        kubectl delete pvc -n $NAMESPACE $pvc-new

        
        echo "Patching original PV: $pv to remove claimRef"
        kubectl patch pv $pv -p '{"spec":{"claimRef": null}}'
        echo "Patching new PV: $pv_new to remove claimRef"
        kubectl patch pv $pv_new -p '{"spec":{"claimRef": null}}'
        echo "Reapplying original PVC: $pvc with volumeName set to new PV: $pv_new"
        cat $NAMESPACE/$WORKLOAD_NAME/original/$pvc.yaml | \
        /usr/bin/yq w - "spec.volumeName" "$pv_new" | \
        kubectl apply -f -

        whiptail --yesno "Delete old pv? Otherwise is may linger as -Available- and maybe cause problems" 10 60

        # check the exit status
        status=$?
        if [ $status = 1 ] || [ $status = 255 ]; then
            echo "User selected No, next in loop"
            continue
        else
            kubectl delete pv $pv
        fi
    done
done



