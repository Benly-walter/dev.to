function Get-RancherClusterAll {
    param (
        [object]$rancher
    )

    $Headers = @{  Authorization = "Bearer $($rancher.token)"; Accept = 'application/json' }
    $rancherRequest = @{ Method = 'Get'; Uri = "https://$($rancher.host)/v3/clusters"; Headers = $Headers }

    $results = (Invoke-RestMethod @rancherRequest -MaximumRetryCount 5).data | Where-Object { $_.name -ne 'local' } | Select-Object id, name, description, provider
    return $results
}
Export-ModuleMember Get-RancherClusterAll

function Get-RancherClusterInfo {
    param (
        [object]$rancher,
        [string]$clusterName
    )

    $Headers = @{  Authorization = "Bearer $($rancher.token)"; Accept = 'application/json' }
    $rancherRequest = @{ Method = 'Get'; Uri = "https://$($rancher.host)/v3/clusters"; Headers = $Headers }

    $results = (Invoke-RestMethod @rancherRequest -MaximumRetryCount 5).data | Where-Object { $_.name -eq $clusterName }
    return $results
}
Export-ModuleMember Get-RancherClusterInfo

function Get-RancherProjectInfo {
    param (
        [object]$rancher,
        [string]$clusterName,
        [string]$projectType = 'system'
    )

    # Get cluster ID from Get-RancherClusterInfo
    $clusterId = Get-RancherClusterInfo -rancher $rancher -clusterName $clusterName | Select-Object -ExpandProperty id

    $Headers = @{  Authorization = "Bearer $($rancher.token)"; Accept = 'application/json' }
    $rancherRequest = @{ Method = 'Get'; Uri = "https://$($rancher.host)/v3/projects"; Headers = $Headers }

    $results = (Invoke-RestMethod @rancherRequest -MaximumRetryCount 5).data | Where-Object { $_.clusterId -eq $clusterId -and $_.name -eq $projectType } | Select-Object id
    return $results
}
Export-ModuleMember Get-RancherProjectInfo

function  New-RancherClusterRoleBinding {
    param (
        [object] $rancher,
        [string] $clusterName,
        [string] $roleTemplateId,
        [string] $groupPrincipalID
    )

    # Get Rancher cluster ID
    $clusterId = Get-RancherClusterInfo -rancher $rancher -clusterName $clusterName | Select-Object -ExpandProperty id

    # Check if role binding already exists
    $Headers = @{ Authorization = "Bearer $($rancher.token)"; Accept = 'application/json' }

    $existingBindings = Invoke-RestMethod -Uri "https://$($rancher.host)/v3/clusterRoleTemplateBindings" -Headers $Headers -Method Get
    $match = $existingBindings.data | Where-Object {
        $_.clusterId -eq $clusterId -and $_.roleTemplateId -eq $roleTemplateId -and $_.groupPrincipalId -eq $groupPrincipalID
    }

    if ($match) {
        Write-Output "Role binding already exists for Cluster: $clusterName, Role: $roleTemplateId, Group: $groupPrincipalID. Skipping..."
        return
    }

    # add new role binding
    $body = @{
        type             = 'clusterRoleTemplateBinding'
        clusterId        = $clusterId
        roleTemplateId   = $roleTemplateId
        groupPrincipalId = $groupPrincipalID
    } | ConvertTo-Json -Depth 3

    $Headers = @{  Authorization = "Bearer $($rancher.token)"; Accept = 'application/json' }
    $rancherRequest = @{ Method = 'Post'; Uri = "https://$($rancher.host)/v3/clusterRoleTemplateBindings"; Headers = $Headers; Body = $Body; ContentType = 'application/json' }

    Invoke-RestMethod @rancherRequest -MaximumRetryCount 5 -UserAgent 'ireckonu'
    if ($?) {
        Write-Output "Successfully created Role Binding for Cluster: $clusterName, Role: $roleTemplateId, Group: $groupPrincipalID."
    } else {
        Write-Output "Failed to create Role Binding for Cluster: $clusterName"
    }

}
Export-ModuleMember New-RancherClusterRoleBinding

function Get-RancherKubeConfig {
    param (
        [object] $rancher,
        [string] $clusterName,
        [string] $kubeConfigFilePath
    )

    # Get Rancher cluster ID
    $clusterId = Get-RancherClusterInfo -rancher $rancher -clusterName $clusterName | Select-Object -ExpandProperty id

    # Rancher API - get kubeConfig
    $Headers = @{  Authorization = "Bearer $($rancher.token)"; Accept = 'application/json' }
    $rancherRequest = @{ Method = 'Post'; Uri = "https://$($rancher.host)/v3/clusters/$($clusterId)?action=generateKubeconfig"; Headers = $Headers }

    $results = Invoke-RestMethod @rancherRequest -MaximumRetryCount 5 -UserAgent 'ireckonu'
    return $results.config

}
Export-ModuleMember Get-RancherKubeConfig

function Merge-KubeConfigFromRancher {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [object] $rancherConfig,

        [Parameter(Mandatory = $true)]
        [string] $targetKubeConfigFile
    )

    process {
        #Create a temporary file to store the kubeconfig content
        $tmpKubeconfigFile = [System.IO.Path]::GetTempFileName()
        Write-Debug "Created temp file : $tmpKubeConfigFile"

        #Write the kubeconfig content to the temporary file
        $rancherConfig | Out-File -FilePath $tmpKubeconfigFile -Encoding UTF8
        Write-Verbose "Writing Rancher config to newly created temp file : $tmpKubeConfigFile"

        # Set the KUBECONFIG environment variable to point to the temporary and existing files
        $env:KUBECONFIG = "$targetKubeConfigFile;$tmpKubeconfigFile"

        # Merge config
        $x = kubectl config view --merge --flatten
        $x | Out-File -FilePath $targetKubeConfigFile -Encoding UTF8
        if ($?) { Write-Verbose "Merged kubeconfig $tmpKubeconfigFile to $targetKubeConfigFile" }
    }
    end {
        # Cleanup: Remove the temporary kubeconfig file when done
        Remove-Item -Path $tmpKubeconfigFile -Force
        Write-Verbose "Cleanup file $tmpKubeconfigFile"
    }

}
Export-ModuleMember Merge-KubeConfigFromRancher