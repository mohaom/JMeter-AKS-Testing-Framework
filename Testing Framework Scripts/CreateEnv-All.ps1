 
$resourceGroup="_ResourceGroup_"
$aksName="_AKSName_"
$location="westeurope"
$aksIdentityName="_AKSIdentityName_"
$acrName="_ContainerRegisteryName_"

az identity create --name $aksIdentityName --resource-group $resourceGroup

$identityId=(az identity show --name $aksIdentityName --resource-group $resourceGroup --query id) | Out-String

az acr create --name $acrName --resource-group $resourceGroup --sku Basic --admin-enabled true

az aks create --resource-group $resourceGroup `
       --name $aksName `
       --node-count 3 `
       --enable-managed-identity `
       --enable-cluster-autoscaler `
       --min-count 1 `
       --max-count 50 `
       --generate-ssh-keys `
	--disable-rbac `
	--node-vm-size Standard_D16s_v3 `
	--location $location `
       --assign-identity $identityId

az acr build -t testframework/jmetermaster:latest -f Dockers/MasterDockerfile -r $acrName .
az acr build -t testframework/jmeterslave:latest -f Dockers/SlaveDockerfile -r $acrName .
az acr build -t testframework/reporter:latest -f Dockers/ReporterDockerfile -r $acrName .

mkdir YamlsOutput
(Get-Content .\YamlsTemplates\reporter.yaml.template).Replace('###acrname###',$acrName) | Set-Content .\YamlsOutput\reporter.yaml
(Get-Content .\YamlsTemplates\jslave.yaml.template).Replace('###acrname###',$acrName) | Set-Content .\YamlsOutput\jslave.yaml
(Get-Content .\YamlsTemplates\jmaster.yaml.template).Replace('###acrname###',$acrName) | Set-Content .\YamlsOutput\jmaster.yaml

az aks get-credentials -n $aksName -g $resourceGroup --admin

az aks update -n $aksName -g $resourceGroup --attach-acr $acrName

kubectl apply -f ./Yamls/azure-premium.yaml
kubectl apply -f ./Yamls/influxdb_svc.yaml
kubectl apply -f ./Yamls/jmeter_influx_configmap.yaml
kubectl apply -f ./YamlsOutput/reporter.yaml

kubectl apply -f ./Yamls/jslaves_svc.yaml
kubectl apply -f ./YamlsOutput/jslave.yaml

kubectl apply -f ./Yamls/jmeter-master-configmap.yaml
kubectl apply -f ./YamlsOutput/jmaster.yaml

$influxdb_pod=((kubectl get pods -o json | ConvertFrom-Json).items.metadata.name | select-string -Pattern 'report').ToString().Trim()

kubectl exec -ti $influxdb_pod -- influx -execute 'CREATE DATABASE jmeter'

kubectl cp ./ConfigurationArtifacts/datasource.json ${influxdb_pod}:/datasource.json
kubectl exec -ti $influxdb_pod -- /bin/bash -c 'until [[ $(curl "http://admin:admin@localhost:3000/api/datasources" -X POST -H "Content-Type: application/json;charset=UTF-8" --data-binary @datasource.json) ]]; do sleep 5; done'

kubectl cp ./ConfigurationArtifacts/jmeterDash.json ${influxdb_pod}:/jmeterDash.json
kubectl exec -ti $influxdb_pod -- curl 'http://admin:admin@localhost:3000/api/dashboards/db' -X POST -H 'Content-Type: application/json;charset=UTF-8' --data-binary '@jmeterDash.json'

$master_pod=((kubectl get pods -o json | ConvertFrom-Json).items.metadata.name | select-string -Pattern 'jmeter-master').ToString().Trim()
kubectl cp ./ConfigurationArtifacts/loady ${master_pod}:/loady



