Param ( [Parameter(Mandatory=$True)] [ValidateNotNull()] $jmxFile, [Parameter(Mandatory=$True)] [ValidateNotNull()] $TestName)


$master_pod=((kubectl get pods -o json | ConvertFrom-Json).items.metadata.name | select-string -Pattern 'jmeter-master').ToString().Trim()

kubectl cp "$jmxFile" "${master_pod}:/$TestName"

Write-Host "------------------------------Executing Test------------------------------" 
kubectl exec -ti $master_pod -- /bin/bash ./loady "$TestName"

Write-Host "------------------------------Done!------------------------------" 
Write-Host "------------------------------Copying Html Report $(${TestName} + "html") ------------------------------" 
$htmlfolder=${TestName}+"html"
$logfile=${TestName}+".txt"

kubectl cp ${master_pod}:$htmlfolder ./$htmlfolder
Write-Host "Done!"

Write-Host "------------------------------Copying logs file $(${logfile} + ".txt") ------------------------------" 

kubectl cp ${master_pod}:$logfile ./$logfile
Write-Host "Done!"

Write-Host "------------------------------Cleaning Environment!------------------------------" 
kubectl exec -it $master_pod -- sh -c $('rm -r ' + $logfile)
kubectl exec -it $master_pod -- sh -c $('rm -r ' + $htmlfolder)
kubectl exec -it $master_pod -- sh -c $('rm -r ' + $TestName)







