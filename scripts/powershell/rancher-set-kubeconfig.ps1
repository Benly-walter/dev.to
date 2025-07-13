param(
    [Parameter(Mandatory = $true)]
    [hashtable]$rancherAccounts,

    [switch]$backupExisting,

    [switch]$recreateConfig,

    [string]$backupPath = [System.IO.Path]::GetTempPath(),

    [string]$kubeConfigFilePath,

    [array]$clusters,

    [ValidateSet('aks', 'k3s')] # add more providers as needed here
    [string]$provider
)


begin {

    $originalErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'

    # import Rancher Functions
    Import-Module -Name ../../modules/rancher.psm1 -Function 'Get-RancherClusterAll', 'Get-RancherClusterInfo', 'Get-RancherKubeConfig', 'Merge-KubeConfigFromRancher' -Force -Verbose

    # Set the default kubeconfig path based on the operating system
    if ($IsWindows) {
        $DefaultKubeconfigPath = "$env:USERPROFILE\.kube\config"
    } elseif ($IsLinux) {
        $DefaultKubeconfigPath = "$env:HOME/.kube/config"
    } elseif ($IsMacOS) {
        $DefaultKubeconfigPath = "$env:HOME/.kube/config"
    } else {
        Write-Error 'Unsupported operating system.'
        return
    }

    # Set default kubeConfigPath if not provided by user
    if ([string]::IsNullOrWhiteSpace($KubeconfigFilePath)) {
        $KubeconfigFilePath = $DefaultKubeconfigPath
    }

    # Check and create kubeconfig file if not present
    if (-not (Test-Path -Path $KubeconfigFilePath)) {
        Write-Output "Kubeconfig file not found at $KubeconfigFilePath. Creating an empty file..."
        New-Item -ItemType File -Path $KubeconfigFilePath -Force | Out-Null
    }

    # Backup existing config file (switch)
    if ($backupExisting.IsPresent) {
        $backupFilePath = "$backupPath" + "kubeConfig_$(Get-Date -Format 'MM-dd-yyyy_hh-mm-ss')"
        Write-Debug '`nPerforming a backup of exisiting kubeConfig file'
        Copy-Item -Path $kubeConfigFilePath -Destination $backupFilePath -Verbose
        Write-Output "Backup file : $backupFilePath`n"
    }

    # Delete existing configuration (switch)
    if ($recreateConfig.IsPresent) {
        Write-Debug '`nRemoving existing config File'
        Remove-Item $kubeConfigFilePath -Force -Confirm
    }

}

process {
    $rancherAccounts.GetEnumerator() | ForEach-Object {

        Write-Output "Working on $($_.Name) environment"
        $clustersAll = @()

        # Get list of clusters with their properties
        $clustersAll = Get-RancherClusterAll -rancher $($_.value)

        # Select clusters to action (if passed by user)
        if ($clusters) {
            Write-Debug 'Selecting clusters to action ..'
            $xClusters = $clusters | ForEach-Object { [PSCustomObject]@{name = $_ } }
            $clustersAll = Compare-Object -ReferenceObject @($clustersAll | Select-Object) -IncludeEqual -DifferenceObject @($xClusters | Select-Object) -Property name -PassThru | Where-Object { $_.SideIndicator -eq '==' }
        }

        if ($provider) {
            Write-Debug "Filtering k8s clusters based on provider to action : $provider.."
            $clustersAll = $clustersAll | Where-Object { $_.provider -eq $provider }
        }

        foreach ($cluster in $clustersAll) {
            Write-Output "Processing cluster $($cluster.name) .."
            Get-RancherKubeConfig -rancher $($_.value) -clusterName $cluster.name | Merge-KubeConfigFromRancher -targetKubeConfigFile $kubeConfigFilePath -Verbose
        }
    }
}

end {
    $ErrorActionPreference = $originalErrorActionPreference
}