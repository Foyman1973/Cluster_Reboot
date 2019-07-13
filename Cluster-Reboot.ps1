 <#
 ==============================================================================================
 
 
 NAME: Cluster-Reboot.ps1
 
 AUTHOR: Jason Foy, DaVita Inc. 
 DATE  : 2/02/2017
 
 COMMENT: PowerCLI script to reboot a selected cluster
 			
 
 ==============================================================================================
#>
Clear-Host
Write-Host ("="*80) -ForegroundColor DarkGreen
Write-Host ""
Write-Host $MyInvocation.MyCommand.Name "v1.1.26"
Write-Host "Started" $(Get-Date -Format g)
Write-Host ""
Write-Host ("="*80) -ForegroundColor DarkGreen
Write-Host ""
Write-Host ""
$yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes","Rock and Roll!"
$no = New-Object System.Management.Automation.Host.ChoiceDescription "&No","Nope, I'm scared!"
$cancel = New-Object System.Management.Automation.Host.ChoiceDescription "&Exit","Eject! Eject! Eject!"
$options = [System.Management.Automation.Host.ChoiceDescription[]]($yes,$no)
$vCenter = Read-Host "vCenter IP or FQDN:"
$stopwatch = [Diagnostics.StopWatch]::StartNew()
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
function Exit-Script{
    Write-Host "Script Exit Requested, Exiting..."
    Stop-Transcript
    exit
}
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
function Get-PowerCLI{
    $pCLIpresent=$false
    Get-Module -Name VMware.VimAutomation.Core -ListAvailable | Import-Module -ErrorAction SilentlyContinue
    try{$pCLIpresent=((Get-Module VMware.VimAutomation.Core).Version.Major -ge 10)}
    catch{}
    return $pCLIpresent
}
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
if(!(Get-PowerCLI)){Write-Host "* * * * No PowerCLI Installed or version too old. * * * *" -ForegroundColor Red;Exit-Script}
$conn = Connect-VIServer $vCenter -ErrorAction SilentlyContinue
if($conn){
    Write-Host "Available Clusters:" -ForegroundColor Yellow
    Write-Host ("="*30) -ForegroundColor DarkGreen
    $clusterList = Get-Cluster|Sort-Object Name
    $choice = @{}
    for($i=1;$i -le $clusterList.count;$i++){
        Write-Host "  $i ...... $($clusterList[$i-1].Name)"
        $choice.Add($i,$($clusterList[$i-1].Name))
    }
    Write-Host ("="*30) -ForegroundColor DarkGreen
    [int]$answer = Read-Host `t"Select Enclosure (1-$($clusterList.count))"
    $myCluster = $choice.Item($answer)
    Write-Host ""
    Write-Host "You Selected:" $myCluster
    Write-Host ""
    
    $title = "Stateless Hosts?";$message = "If these are Stateless Autodeploy Hosts, choose Yes."
    $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes,$no)
    $result = $host.UI.PromptForChoice($title, $message, $options, 1)
    Write-Host ""
    switch($result){
        0{$stateless = $true}
        1{$stateless = $false}
    }
    Write-Host ("-"*50) -ForegroundColor DarkGreen
    Write-Host ""
    Write-Host "The Following Hosts will be rebooted:" -ForegroundColor Yellow
    Write-Host ("-"*50) -ForegroundColor DarkRed
    $hostList = Get-Cluster $myCluster|Get-VMHost|Where-Object{$_.ConnectionState -match "^(Connected|Maintenance)$"}|Sort-Object Name
    $connCount = 0;$maintCount = 0
    $hostList|ForEach-Object{
        if($_.ConnectionState -eq "Maintenance"){
            $maintCount++
            Write-Host $_.Name "[" -NoNewline;Write-Host $_.ConnectionState -ForegroundColor Yellow -NoNewline;Write-Host "]"
        }
        else{
            $connCount++
            Write-Host $_.Name "[" -NoNewline;Write-Host $_.ConnectionState -ForegroundColor Green -NoNewline;Write-Host "]"
        }
    }
    if($maintCount -gt 0){
        Write-Host ""
        Write-Host `t`t"!! Hosts In Maintenance Mode !!"`t`t`t -ForegroundColor Yellow -BackgroundColor Black
        Write-Host "Rebooting STATELESS hosts in Maintenance Mode will automatically"
        Write-Host "place them online with the cluster after reboot.  If these hosts"
        Write-Host "are offline for hardware or other issues this may endanger the"
        write-host "cluster guests after it reboots!"
        Write-Host `t`t"!! Hosts In Maintenance Mode !!"`t`t`t -ForegroundColor Yellow -BackgroundColor Black
        Write-Host ""
        $title = "Include Maintenance Hosts?";$message = "Choosing NO will reboot only Online Hosts in $myCluster."
        $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes,$no,$cancel)
        $result = $host.UI.PromptForChoice($title, $message, $options, 1)
        Write-Host ""
        switch($result){
            0{Write-Host "You have selected to reboot ALL Hosts." -ForegroundColor Yellow;$rebootAll = $true}
            1{Write-Host "You have selected to reboot Online Hosts ONLY." -ForegroundColor Green;$rebootAll = $false}
            2{Write-Host "Aborting Process!" -ForegroundColor Red;exit}
        }
        Write-Host ""
    }
    Write-Host ("-"*50) -ForegroundColor DarkRed
    $title = "Reboot Cluster?";$message = "Choosing Yes will start a systematic restart of cluster $myCluster."
    $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes,$no)
    $result = $host.UI.PromptForChoice($title, $message, $options, 1)
    Write-Host ""
    switch($result){
    	0{
            Write-Host "Cluster Reboot Requested.  Rebooting " -NoNewline
            if($rebootAll){Write-Host "ALL" -ForegroundColor Yellow -BackgroundColor Black -NoNewline}
            else{
                Write-Host "ONLINE ONLY" -ForegroundColor Green -NoNewline
                $hostList = Get-Cluster $myCluster|Get-VMHost|Where-Object{$_.ConnectionState -eq "Connected"}|Sort-Object Name
            }
            Write-Host " hosts in cluster " -noNewLine;Write-Host $myCluster -ForegroundColor Cyan
            $i=1
            $hostCount = $hostList.Count
            $hostList|ForEach-Object{
                Write-Progress -Activity "Rebooting Cluster $myCluster" -Status "$($_.Name) [ $i of $hostCount ]" -PercentComplete (($i/$hostCount)*100)
                if($_.ConnectionState -ne "Maintenance"){
                	$alreadyMaint = $false
                    Write-Host "Placing host " -NoNewline
                    Write-Host $_.Name -ForegroundColor Cyan -NoNewline
                    Write-Host " into Maintenance..."
                    $result = $_|Set-VMHost -State Maintenance
                }
                else{
                	$alreadyMaint = $true
                	Write-Host "Host " -NoNewline
                    Write-Host $_.Name -ForegroundColor Cyan -NoNewline
                    Write-Host " already in Maintenance..."
                }
                if((Get-VMHost $_).ConnectionState -eq "Maintenance"){
                    Write-Host `t"Rebooting Host " $_.Name
                    $result = $_|Restart-VMHost -Confirm:$false
                    do{Start-Sleep -Seconds 10}
                    until( (Get-VMHost $_).ConnectionState -eq "NotResponding")
                    Write-Host `t"Host offline, waiting for return..."
                    do{Start-Sleep -Seconds 10}
                    until((Get-VMHost $_).ConnectionState -ne "NotResponding")
                    
                    if($stateless){
                    	Write-Host `t"Host is responding again, waiting for profiles..."
	                    do{Start-Sleep -Seconds 10}
	                    until((Get-VMHost $_).ConnectionState -eq "Connected")
                    }
                    else{
                    	if(!($alreadyMaint)){
	                    	do{Start-Sleep -Seconds 5}
	                    	until((Get-VMHost $_).ConnectionState -eq "Maintenance")
	                    	Write-Host `t"Exiting Maintenance mode..."
	                    	$result = $_|Set-VMHost -State Connected
                    	}
                    }
                    Start-Sleep -Seconds 15
                    Write-Host `t"Host Reboot complete." -ForegroundColor Green
                    $i++
                }
                else{Write-Host "Host is not in maintenance, unable to reboot." -ForegroundColor Red}
            }
            Write-Host "Cluster Reboot Process completed." -ForegroundColor Green
        }
    	1{Write-Host "Cluster Reboot Aborted." -ForegroundColor Red}
    }
}
else{write-host "Failed to conntect to $vCenter" -ForegroundColor Red}
$stopwatch.Stop()
$elapsedTime = [Math]::Round((($stopwatch.ElapsedMilliseconds)/1000)/60,1)
Write-Host ("="*80) -ForegroundColor DarkGreen
Write-Host ("="*80) -ForegroundColor DarkGreen
Write-Host ""
Write-Host "Script completed in $elapsedTime minutes(s)"
Write-Host ""
Write-Host ("="*80) -ForegroundColor DarkGreen
