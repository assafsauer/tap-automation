# /bin/bash


################## vars ##################
##########################################

mgmt_cluster=mgmt
cluster=tap-c4
export tap_namespace=dev


export HARBOR_USER=xxx
export HARBOR_PWD=Txxx
export HARBOR_DOMAIN=harbor.source-lab.io

export INSTALL_REGISTRY_HOSTNAME=registry.tanzu.vmware.com
export INSTALL_REGISTRY_USERNAME=xxx
export INSTALL_REGISTRY_PASSWORD=xxx

export token=2xxxx
export domain=source-lab.io


###  TAP Version ####
tap_version=1.3.1-build.4 #pivnet... release-version='1.3.1-build.4' --product-file-id=1310085
framework_linux_md64=1310085
gui_blank_Catalog=1099786
gui_Yelb_Catalog=1073911
essential==1263760
export VERSION=v0.25.0 #sudo install cli/core/$VERSION/tanzu-core-linux_amd64 /usr/local/bin/tanzu


### optional: TAP GUI ####
export git_token=xxxx
export catalog_info=https://github.com/assafsauer/tap-catalog-2/blob/main/catalog-info.yaml
export repo_owner=xxxx
export  repo_name=spring-petclinic-accelerators 
sshkey=xxx

### provider ###
export infrastructure_provider=aws
export LBType=nlb

 
  
################## Download TAP packeges ##################
###########################################################

### login to pivotal network ###

wget  https://github.com/pivotal-cf/pivnet-cli/releases/download/v3.0.1/pivnet-linux-amd64-3.0.1
chmod 777 pivnet-linux-amd64-3.0.1
cp pivnet-linux-amd64-3.0.1 /usr/local/bin/pivnet
pivnet login --api-token=$token

#### Download TAP 4.0 ####


### download tanzu-CLI -tanzu-framework-linux-amd64.tar
pivnet download-product-files --product-slug='tanzu-application-platform' --release-version=$tap_version --product-file-id=$framework_linux_md64

### GUI catalog:  tap-gui-yelb-catalog.tgz , tap-gui-blank-catalog.tgz

pivnet download-product-files --product-slug='tanzu-application-platform' --release-version=$tap_version --product-file-id=$gui_blank_Catalog
pivnet download-product-files --product-slug='tanzu-application-platform' --release-version=$tap_version --product-file-id=$gui_Yelb_Catalog


################## K8s Prep  ##################
###############################################


##### confirm K8s cluster requirements before execution ####

echo "Minimum requirements for tap: 4 CPUs , 16 GB RAM and at least 3 nodes"

node=$(kubectl get nodes | awk '{if(NR==2) print $1}')
kubectl describe nodes $node | grep -A 7 Capacity:


read -p "does your Kubernetes cluster meet the requirements? (enter: yes to continue)"
if [ "$REPLY" != "yes" ]; then
   exit
fi

echo "starting installation"

### patch mgmt cluster ###

kubectl config use-context $mgmt_cluster"-admin@"$mgmt_cluster

kubectl patch app/"$cluster"-kapp-controller -n default --patch '{"spec":{"paused":true}}' --type=merge

kubectl config use-context $cluster"-admin@"$cluster

kubectl create clusterrolebinding default-tkg-admin-privileged-binding --clusterrole=psp:vmware-system-privileged
kubectl create clusterrolebinding my-privileged-cluster-role-binding \
 --clusterrole=vmware-system-tmc-psp-privileged \
 --group=system:authenticated

kubectl create ns $tap_namespace
kubectl create ns tap-install

### create storageclass ###

wget -N https://raw.githubusercontent.com/assafsauer/tap-automation/master/templates/storage-class.yml
kubectl apply -f storage-class.yml  

### git token secret ###
wget -N https://raw.githubusercontent.com/assafsauer/tap-automation/master/templates/git-secret.yml
envsubst <  git-secret.yml > git-secret.yaml 
kubectl apply -f git-secret.yaml -n $tap_namespace


### rbac overlay workaround for 1.2 ###
wget -N https://raw.githubusercontent.com/assafsauer/tap-automation/master/templates/rbac.overlay.yml
#envsubst <  rbac.overlay.yml > rbac.overlay.yaml
kubectl create secret generic k8s-reader-overlay --from-file=rbac.overlay.yml -n tap-install


### cluster essential ####

#pivnet download-product-files --product-slug='tanzu-cluster-essentials' --release-version='1.2.0' --product-file-id=$essential

#export INSTALL_BUNDLE=registry.tanzu.vmware.com/tanzu-cluster-essentials/cluster-essentials-bundle@sha256:e00f33b92d418f49b1af79f42cb13d6765f1c8c731f4528dfff8343af042dc3e

#tar -xvf tanzu-cluster-essentials-linux-amd64-1.2.0.tgz -C tanzu-cluster-essentials/
#cd tanzu-cluster-essentials
#./install.sh --yes
#cd ..

################## update tap plugins ##################
###########################################################

rm -r tanzu
mkdir tanzu
tar -xvf tanzu-framework-linux-amd64.tar -C tanzu/
cd tanzu
export TANZU_CLI_NO_INIT=true
#tanzu plugin delete imagepullsecret
#tanzu config set features.global.context-aware-cli-for-plugins false


sudo install cli/core/$VERSION/tanzu-core-linux_amd64 /usr/local/bin/tanzu
tanzu plugin install --local cli all
cd ..

#imgpkg copy -b registry.tanzu.vmware.com/tanzu-application-platform/tap-packages:${tap_version} --to-repo ${HARBOR_DOMAIN}/tap/tap-packages

### cluster prep ###

kubectl create ns tap-install

kubectl delete deployment kapp-controller -n tkg-system
kubectl apply -f https://github.com/vmware-tanzu/carvel-kapp-controller/releases/download/v0.29.0/release.yml

kubectl create ns secretgen-controller
kubectl apply -f https://github.com/vmware-tanzu/carvel-secretgen-controller/releases/latest/download/release.yml

#kapp deploy -y -a sg -f https://github.com/vmware-tanzu/carvel-secretgen-controller/releases/download/v0.6.0/release.yml



#### RBAC ####
wget -N https://raw.githubusercontent.com/assafsauer/tap-automation/master/templates/serviceacount.yml
kubectl apply -f serviceacount.yml -n $tap_namespace



################## Secrets ##################
#############################################

#### validating access /exist script if login fail #####


echo "#####  checking credentials for Tanzu Network and Regsitry ######"
if docker login -u ${HARBOR_USER} -p ${HARBOR_PWD} ${HARBOR_DOMAIN}; then
  echo "login successful to" ${HARBOR_DOMAIN}  >&2
else
  ret=$?
  echo "########### exist installation , please change credentials for  ${HARBOR_DOMAIN} $ret" >&2
  exit $ret
fi


if docker login -u ${INSTALL_REGISTRY_USERNAME} -p ${INSTALL_REGISTRY_PASSWORD} ${INSTALL_REGISTRY_HOSTNAME}; then
  echo "login successful to" ${INSTALL_REGISTRY_HOSTNAME} >&2
else
  ret=$?
  echo "########### exist installation , please change credentials for ${INSTALL_REGISTRY_HOSTNAME} $ret" >&2
  exit $ret
fi


#### adding secrets #####
echo  "#### adding cred ####"
tanzu secret registry add tap-registry \
  --username ${INSTALL_REGISTRY_USERNAME} --password ${INSTALL_REGISTRY_PASSWORD} \
  --server ${INSTALL_REGISTRY_HOSTNAME} \
  --export-to-all-namespaces --yes --namespace tap-install

tanzu secret registry add harbor-registry -y \
--username ${HARBOR_USER} --password ${HARBOR_PWD} \
--server ${HARBOR_DOMAIN}  \
 --export-to-all-namespaces --yes --namespace tap-install


### temp workaround for the "ServiceAccountSecretError" issue
kubectl create secret docker-registry registry-credentials --docker-server=${HARBOR_DOMAIN} --docker-username=${HARBOR_USER} --docker-password=${HARBOR_PWD} -n tap-install 

kubectl create secret docker-registry registry-credentials --docker-server=${HARBOR_DOMAIN} --docker-username=${HARBOR_USER} --docker-password=${HARBOR_PWD} -n $tap_namespace

kubectl create secret docker-registry harbor-registry --docker-server=${HARBOR_DOMAIN} --docker-username=${HARBOR_USER} --docker-password=${HARBOR_PWD} -n dev


#echo "your harbor cred"
#kubectl get secret registry-credentials --output="jsonpath={.data.\.dockerconfigjson}" | base64 --decode

wget -N https://raw.githubusercontent.com/assafsauer/tap-automation/master/templates/tap-values.yml 
envsubst < tap-values.yml > tap-base-final.yml


echo "###### adding tap package #####"
sleep 15

#tanzu package repository add tanzu-tap-repository \
#  --url registry.tanzu.vmware.com/tanzu-application-platform/tap-packages:$tap_version \
#  --namespace tap-install


## offline 
tanzu package repository add tanzu-tap-repository --url harbor.source-lab.io/tap/tap-packages:$tap_version --namespace tap-install

echo "tap-repository added successfully"

sleep 60

##################  TAP installation ##################
#######################################################


echo "####  starting installtion in 10 sec (Please be patient as it might take few min to complete) ######"
sleep 10

tanzu package install tap -p tap.tanzu.vmware.com -v $tap_version --values-file tap-base-final.yml -n tap-install

sleep 30

echo "installtion completed"

read -p "would you like to setup TAP GUI ? (enter: yes to continue)"
if [ "$REPLY" != "yes" ]; then
   exit
fi




tap_domain=$(kubectl get svc -n tap-gui |awk 'NR=='2'{print $4}')
export tap_domain=$tap_domain

ingress=$( kubectl get svc -A |grep tanzu-system-ingress |grep LoadBalancer | awk 'NR=='1'{print $5}')
ip=$(nslookup $ingress |grep Address |grep -v 127 | awk '{print $2}')

echo "########## please update your DNS as follow: ###########"
echo *app.$domain "pointing to" $ip

wget -N https://raw.githubusercontent.com/assafsauer/tap-automation/master/templates/tap-values-gui.yml
envsubst < tap-values-gui.yml > tap-gui-final-val.yml
tanzu package installed update --install tap -p tap.tanzu.vmware.com -v $tap_version -n tap-install --poll-timeout 30m -f tap-gui-final-val.yml 


read -p "would you like to add testing and scan to the supplychain ? (enter: yes to continue)"
if [ "$REPLY" != "yes" ]; then
   exit
fi

#### scan and tests #####
wget -N https://raw.githubusercontent.com/assafsauer/tap-automation/master/templates/scanpolicy.yml
kubectl apply -f scanpolicy.yml -n $tap_namespace

wget -N https://raw.githubusercontent.com/assafsauer/tap-automation/master/templates/tekton.yml
kubectl apply -f tekton.yml -n $tap_namespace

wget -N https://raw.githubusercontent.com/assafsauer/tap-automation/master/templates/tap-test-scan.yml
envsubst < tap-test-scan.yml > tap-test-scan.yaml
tanzu package installed update --install tap -p tap.tanzu.vmware.com -v $tap_version -n tap-install --poll-timeout 30m -f tap-test-scan.yaml 

echo "TAP is Ready to go"
