param(
  [Parameter(mandatory=$true)][String]$sourceOrg,
  [Parameter(mandatory=$true)][String]$sourceProject,
  [Parameter(mandatory=$true)][String]$sourceUsername,
  [Parameter(mandatory=$true)][String]$sourcePAT,
  [Parameter(mandatory=$false)][String]$destOrg,
  [Parameter(mandatory=$true)][String]$destProject,
  [Parameter(mandatory=$false)][String]$destPAT,
  [Parameter(mandatory=$false)][String]$destUsername,
  [Parameter(mandatory=$false)][String]$ReflectedWorkItemField = "Custom.ReflectedWorkItemId",
  [switch]$clean,
  [switch]$cloneRepos,
  [switch]$createRemotes,
  [switch]$createForks,
  [switch]$createPullRequests,
  [switch]$pushRepos
)

# Default the destination PAT token, Organisation and Username to match the source if not supplied
if(-not $destPAT){ $destPAT = $sourcePAT }
if(-not $destOrg){ $destOrg = $sourceOrg }
if(-not $destUsername){ $destUsername = $sourceUsername }

$errorfiletimestamp = Get-Date -Format FileDateTime

function Out-ErrorLog($message) {
  $timestamp = get-date -Format FileDateTime
  "[$timestamp] $message" | Out-File -Append "${PSScriptRoot}/error-$errorfiletimestamp.log"
  Write-Warning $message
}

function Write-Banner {
  param(
    [String]$message
  )
  Write-Output ""
  Write-Output "================================================================================"
  Write-Output $message
  Write-Output "================================================================================"
  Write-Output ""
}
function Get-BasicAuthHeader {
  Param(
    [Parameter(Mandatory=$true)]
    [string]$Name,
    [Parameter(Mandatory=$true)]
    [string]$PAT
)

  $Auth = '{0}:{1}' -f $Name, $PAT
  $Auth = [System.Text.Encoding]::UTF8.GetBytes($Auth)
  $Auth = [System.Convert]::ToBase64String($Auth)
  $Header = @{Authorization=("Basic {0}" -f $Auth)}
  $Header
}

function CreateRepo {
  param (
    [Parameter(mandatory=$true)][String]$Org,
    [Parameter(mandatory=$true)][String]$Project,
    [Parameter(mandatory=$true)][String]$Username,
    [Parameter(mandatory=$true)][String]$PAT,
    [Parameter(mandatory=$true)][String]$repoName
  )

  $projectID = GetProjectId -Org $Org -Project $Project -Username $Username -PAT $PAT

  $body = @{
    name="$repoName"
    project=@{
      id="$projectID"
    }
  } | ConvertTo-JSON

  try{
    Write-Output "Creating repository '$Org/$Project/$repoName'"
    Invoke-AzureDevOpsAPI -Org $Org -Function "git/repositories" -Username $Username -PAT $PAT -HTTPMethod "POST" -Body $body -ErrorAction SilentlyContinue | Out-Null
  } catch {
    Out-ErrorLog ($_.ErrorDetails.Message | ConvertFrom-Json).message
  }

}

function CreatePullRequest {
  param (
    [Parameter(mandatory=$true)][String]$Org,
    [Parameter(mandatory=$true)][String]$Project,
    [Parameter(mandatory=$true)][String]$Username,
    [Parameter(mandatory=$true)][String]$PAT,
    [Parameter(mandatory=$true)][String]$RepoId,
    [Parameter(mandatory=$true)]$PullRequest
  )

  $body = $PullRequest | ConvertTo-JSON

  try{
    Write-Host "Creating pull request '$Org/$Project/$RepoId/$($PullRequest.pullRequestId)'"
    return (Invoke-AzureDevOpsAPI -Org $Org -Function "git/repositories/$RepoId/pullrequests" -Username $Username -PAT $PAT -HTTPMethod "POST" -Body $body -ErrorAction SilentlyContinue).Content | ConvertFrom-Json
  } catch {
    Out-ErrorLog ($_.ErrorDetails.Message | ConvertFrom-Json).message
  }

}

function CreatePullRequestThread {
  param (
    [Parameter(mandatory=$true)][String]$Org,
    [Parameter(mandatory=$true)][String]$Project,
    [Parameter(mandatory=$true)][String]$Username,
    [Parameter(mandatory=$true)][String]$PAT,
    [Parameter(mandatory=$true)][String]$RepoId,
    [Parameter(mandatory=$true)]$PullRequestId,
    [Parameter(mandatory=$true)]$PullRequestThread
  )

  $body = $PullRequestThread | ConvertTo-JSON

  try{
    Write-Output "Creating PR Thread '$Org/$Project/$RepoId/$PullRequestId'"
    return (Invoke-AzureDevOpsAPI -Org $Org -Function "git/repositories/$RepoId/pullrequests/$PullRequestId/threads" -Username $Username -PAT $PAT -HTTPMethod "POST" -Body $body -ErrorAction SilentlyContinue).Content | ConvertFrom-Json
  } catch {
    Out-ErrorLog ($_.ErrorDetails.Message | ConvertFrom-Json).message
  }

}

function Invoke-AzureDevOpsAPI {
  param(
    $Username,
    $PAT,
    $Org,
    $Project,
    $HTTPMethod="GET",
    $Function,
    $Parameters,
    $Body,
    $APIVersion="5.1",
    $ContentType="Application/JSON"
  )

  if($Project){
    $Org += "/$Project"
  }
  
  if ($Org -like 'https://*') {
    $FinalOrgBase = $Org;
  }
  else
  {
    $FinalOrgBase = "https://dev.azure.com/${Org}"
  }

  $headers = Get-BasicAuthHeader $Username $PAT
  if($HTTPMethod -eq "GET"){
    $queryString = ""
    if($Parameters.Keys){
      $Parameters.Keys | ForEach-Object { $queryString += $_ + "=" + $Parameters[$_] + "&" }
    }
    Write-Debug "${FinalOrgBase}/_apis/${Function}?${queryString}api-version=${APIVersion}"
    return Invoke-WebRequest "${FinalOrgBase}/_apis/${Function}?${queryString}api-version=${APIVersion}" -UseBasicParsing -Headers $Headers -Method GET -Body $Body -ContentType $ContentType
  }
    Write-Debug "${FinalOrgBase}/_apis/${Function}?${queryString}api-version=${APIVersion}"
  return Invoke-WebRequest "${FinalOrgBase}/_apis/${Function}?api-version=${APIVersion}" -UseBasicParsing -Headers $Headers -Method $HTTPMethod -Body $Body -ContentType $ContentType

}

function Invoke-AzureDevOpsWikiAPI {
  param(
    $Username,
    $PAT,
    $Org,
    $Project,
    $HTTPMethod="GET",
    $Function,
    $Parameters,
    $Body,
    $APIVersion="5.1",
    $ContentType="Application/JSON"
  )

  if($Project){
    $Org += "/$Project"
  }

  if ($Org -like 'https://*') {
    $FinalOrgBase = $Org;
  }
  else
  {
    $FinalOrgBase = "https://dev.azure.com/${Org}"
  }
  
  $headers = Get-BasicAuthHeader $Username $PAT


  return Invoke-WebRequest "${FinalOrgBase}/_apis/${Function}" -UseBasicParsing -Headers $Headers -Method $HTTPMethod -Body $Body -ContentType $ContentType

}

function CreateFork {
  param (
    [Parameter(mandatory=$true)][String]$Org,
    [Parameter(mandatory=$true)][String]$Project,
    [Parameter(mandatory=$true)][String]$Username,
    [Parameter(mandatory=$true)][String]$PAT,
    [Parameter(mandatory=$true)][String]$forkName,
    [Parameter(mandatory=$true)][String]$parentName,
    [Parameter(mandatory=$true)][String]$parentProject

  )

  $projectID = GetProjectId -Org $Org -Project $Project -Username $Username -PAT $PAT
  try{
    $parentProjectID = GetProjectId -Org $Org -Project $parentProject -Username $Username -PAT $PAT
    $parentRepoID = GetRepoId -Org $Org -Project $parentProject -Username $Username -PAT $PAT -repoName $parentName
  } catch {
    Out-ErrorLog ($_.ErrorDetails.Message | ConvertFrom-Json).message
  }

  if(!$parentProjectID){
    Out-ErrorLog "Parent repository not found for fork $sourceProject/$($repo.name)"
    Out-ErrorLog "Creating a plain repository instead"
    CreateRepo -Org $Org -Project $Project -Username $Username -PAT $PAT -repoName $forkName
  } else {

    $body = @{
      name="$forkName"
      project=@{
        id="$projectID"
      }
      parentRepository=@{
        id="$parentRepoID"
        project=@{
          id="$parentProjectID"
        }
      }
    } | ConvertTo-JSON

    try{
      Write-Output "Creating fork '$Project/$forkName' downstream from '$parentProject/$parentName'"
      Invoke-AzureDevOpsAPI -Org $Org -Function "git/repositories" -Username $Username -PAT $PAT -HTTPMethod "POST" -Body $body -ErrorAction SilentlyContinue | Out-Null
    } catch {
      Out-ErrorLog ($_.ErrorDetails.Message | ConvertFrom-Json).message
    }
  }

}

function GetProjectId {
  param (
    [Parameter(mandatory=$true)][String]$Org,
    [Parameter(mandatory=$true)][String]$Project,
    [Parameter(mandatory=$true)][String]$Username,
    [Parameter(mandatory=$true)][String]$PAT
  )

  $response = Invoke-AzureDevOpsAPI -Org $Org -Function "projects/$Project" -Username $Username -PAT $PAT | ConvertFrom-Json
  return $response.id
}

function GetPullRequests {
  param (
    [Parameter(mandatory=$true)][String]$Org,
    [Parameter(mandatory=$true)][String]$Project,
    [Parameter(mandatory=$true)][String]$Username,
    [Parameter(mandatory=$true)][String]$PAT
  )

  $parameters = @{}
  $response = Invoke-AzureDevOpsAPI -Org $Org -Project $Project -Function "git/pullrequests" -Parameters $parameters -Username $Username -PAT $PAT | ConvertFrom-Json
  return $response.value
}

function GetPullRequest {
  param (
    [Parameter(mandatory=$true)][String]$Org,
    [Parameter(mandatory=$true)][String]$Project,
    [Parameter(mandatory=$true)][String]$Username,
    [Parameter(mandatory=$true)][String]$PAT,
    [Parameter(mandatory=$true)][Number]$PullRequestId
  )

  $parameters = @{}
  $response = Invoke-AzureDevOpsAPI -Org $Org -Project $Project -Function "git/pullrequests/$PullRequestId" -Parameters $parameters -Username $Username -PAT $PAT | ConvertFrom-Json
  return $response
}

function GetPullRequestThreads {
  param (
    [Parameter(mandatory=$true)][String]$Org,
    [Parameter(mandatory=$true)][String]$Project,
    [Parameter(mandatory=$true)][String]$Username,
    [Parameter(mandatory=$true)][String]$PAT,
    [Parameter(mandatory=$true)]$RepoIdOrName,
    [Parameter(mandatory=$true)]$PullRequestId
  )

  $parameters = @{}
  $response = Invoke-AzureDevOpsAPI -Org $Org -Project $Project -Function "git/repositories/$RepoIdOrName/pullrequests/$PullRequestId/threads" -Parameters $parameters -Username $Username -PAT $PAT | ConvertFrom-Json
  return $response.value
}

function GetWorkReflectedWorkItem {
  param (
    [Parameter(mandatory=$true)][String]$Org,
    [Parameter(mandatory=$true)][String]$Username,
    [Parameter(mandatory=$true)][String]$PAT,
    [Parameter(mandatory=$true)]$WorkItemUrl
  )

  $parameters = @{}
  $response = Invoke-AzureDevOpsAPI -HTTPMethod "POST" -Body (@{query = "select [System.Id] from WorkItems where [$ReflectedWorkItemField] = '$WorkItemUrl'"} | ConvertTo-JSON ) -Org $Org -Project $Project -Function "wit/wiql" -Parameters $parameters -Username $Username -PAT $PAT
  $response = $response | ConvertFrom-Json
  if ($null -ne $response.workItems -and $response.workItems.Count -gt 1) {
    Write-Warning "Found multiple work items with reflected work item reference $WorkItemUrl."
  }
  return $response.workItems | Select-Object -First 1
}

function GetPullRequestWorkItems {
  param (
    [Parameter(mandatory=$true)][String]$Org,
    [Parameter(mandatory=$true)][String]$Project,
    [Parameter(mandatory=$true)][String]$Username,
    [Parameter(mandatory=$true)][String]$PAT,
    [Parameter(mandatory=$true)]$RepoIdOrName,
    [Parameter(mandatory=$true)]$PullRequestId
  )

  $parameters = @{}
  $response = Invoke-AzureDevOpsAPI -Org $Org -Project $Project -Function "git/repositories/$RepoIdOrName/pullrequests/$PullRequestId/workitems" -Parameters $parameters -Username $Username -PAT $PAT | ConvertFrom-Json
  return $response.value
}

function GetRepoId {
  param (
    [Parameter(mandatory=$true)][String]$Org,
    [Parameter(mandatory=$true)][String]$Project,
    [Parameter(mandatory=$true)][String]$Username,
    [Parameter(mandatory=$true)][String]$PAT,
    [Parameter(mandatory=$true)][String]$repoName
  )

  return (GetRepo -Org $Org -Project $Project -Username $Username -PAT $PAT -RepoName $repoName).id
}

function GetRepo {
  param (
    [Parameter(mandatory=$true)][String]$Org,
    [Parameter(mandatory=$true)][String]$Project,
    [Parameter(mandatory=$true)][String]$Username,
    [Parameter(mandatory=$true)][String]$PAT,
    [Parameter(mandatory=$true)][String]$repoName
  )

  $parameters = @{includeParent="true"}
  $response = Invoke-AzureDevOpsAPI -Org $Org -Project $Project -Function "git/repositories/${repoName}" -Parameters $parameters -Username $Username -PAT $PAT | ConvertFrom-Json
  return $response
}

function ListRepos {
  param (
    [Parameter(mandatory=$true)][String]$Org,
    [Parameter(mandatory=$true)][String]$Project,
    [Parameter(mandatory=$true)][String]$Username,
    [Parameter(mandatory=$true)][String]$PAT
  )

  $parameters = @{
    includeAllUrls="true"
    includeLinks="true"
  }

  $response =  Invoke-AzureDevOpsWikiAPI -Org $Org -Project $Project -Function "git/repositories?includeHidden=True" -Parameters $parameters -Username $Username -PAT $PAT | ConvertFrom-JSON
  return $response.value
}

function GetForkParentRepository {
  param (
    [Parameter(mandatory=$true)][String]$Org,
    [Parameter(mandatory=$true)][String]$Project,
    [Parameter(mandatory=$true)][String]$Username,
    [Parameter(mandatory=$true)][String]$forkName,
    [Parameter(mandatory=$true)][String]$PAT
  )

  $parameters = @{includeParent="true"}
  $response =  Invoke-AzureDevOpsAPI -Org $Org -Project $Project -Function "git/repositories/${forkName}" -Parameters $parameters -Username $Username -PAT $PAT | ConvertFrom-JSON

  if(Get-Member -inputobject $response -name "parentRepository" -Membertype Properties){
    return $response.parentRepository
  }

  return $null

}

if($clean){
  Remove-Item -Recurse -Force "$PSScriptRoot/repositories"
}

New-Item -ItemType Directory "$PSScriptRoot/repositories/$sourceProject" -ErrorAction SilentlyContinue

$allSourceRepos = ListRepos -Org $sourceOrg -Project $sourceProject -PAT $sourcePAT -Username $sourceUsername

if($cloneRepos){
  Write-Banner "Cloning repositories from '$sourceOrg/$sourceProject' to local disk"
  foreach($repo in $allSourceRepos){
    $localrepo =  "$PSScriptRoot/repositories/$sourceProject/$($repo.name).git"
    if(Test-Path $localrepo){
      Push-Location $localrepo
      Write-Output "Updating existing repository $localrepo"
      git fetch origin +refs/heads/*:refs/heads/* --prune
      Pop-Location
    }
    else{
      Write-Output "Cloning new repository $localrepo"
      git clone --bare ($repo.webUrl -replace "://","://$($sourceUsername):$sourcePAT@") $localrepo | Out-Null
    }
    Write-Output ""
  }
}

if($createRemotes){
  Write-Banner "Creating repositories on '$destOrg/$destProject' from '$sourceOrg/$sourceProject'"

  $sourceRepos = $allSourceRepos | Where-Object { $_.isFork -ne $True }
  if(@($sourceRepos).length -gt 0){
    foreach($repo in $sourceRepos){
      $localrepo = "$PSScriptRoot/repositories/$sourceProject/$($repo.name).git"
      CreateRepo -Org $destOrg -Project $destProject -PAT $destPAT -Username $destUsername -repoName $repo.name
      Write-Output ""
    }
  } else {
    Write-Warning "No repositories found in $sourceOrg/$sourceProject"
  }
}

if($createForks){
  Write-Banner @"
Creating forks on '$destOrg/$destProject' from '$sourceOrg/$sourceProject'
Any missing references will result in a normal repository being created instead
"@

  $sourceForks = $allSourceRepos | Where-Object { $_.isFork -eq $True }
  if(@($sourceForks).length -gt 0){
    foreach($repo in $sourceForks){
      $localrepo = "$PSScriptRoot/repositories/$sourceProject/$($repo.name).git"

      $forkParent = GetForkParentRepository -Org $sourceOrg -Project $sourceProject -PAT $sourcePAT -Username $sourceUsername -forkName $repo.name
      if($forkParent){
        CreateFork -Org $destOrg -Project $destProject -PAT $destPAT -Username $destUsername -forkName $repo.name -parentName $forkParent.name -parentProject $forkParent.project.name
      } else {
        Out-ErrorLog "Parent repository not found for fork $sourceProject/$($repo.name)"
        Out-ErrorLog "Creating a plain repo instead"
        CreateRepo -Org $destOrg -Project $destProject -PAT $destPAT -Username $destUsername -repoName $repo.name
      }
      Write-Output ""
    }
  } else {
    Write-Warning "No forks found in $sourceOrg/$sourceProject"
  }
}

if($pushRepos){
  Write-Banner "Pushing to all repositories in '$destOrg/$destProject'"

  $allDestRepos = ListRepos -Org $destOrg -Project $destProject -PAT $destPAT -Username $destUsername
  foreach($repo in $allDestRepos){
    $localrepo = "$PSScriptRoot/repositories/$sourceProject/$($repo.name).git"
    if(Test-Path $localrepo){
      Write-Output "Pushing local bare repo $($repo.name).git to $($repo.sshUrl)"
      Set-Location $localrepo
      git push --mirror ($repo.webUrl -replace "://","://$($destUsername):$destPAT@")
      Write-Output ""
    } else {
      Out-ErrorLog "Local repo not found: $localrepo"
    }
  }
}

if($createPullRequests){
  Write-Banner @"
Creating pull requests on '$destOrg/$destProject' from '$sourceOrg/$sourceProject'
"@

  $sourcePullRequests = GetPullRequests -Org $sourceOrg -Project $sourceProject -PAT $sourcePAT -Username $sourceUsername

  if(@($sourcePullRequests).length -gt 0){
    foreach($pr in $sourcePullRequests){

      Write-Output "Fetching source merge $($pr.mergeId).."
      $sourceThreads = GetPullRequestThreads -Org $SourceOrg -Project $pr.repository.project.id -Username $sourceUsername -PAT $sourcePAT -RepoIdOrName $pr.repository.name -PullRequestId $pr.pullRequestId
      $sourceWorkItems = GetPullRequestWorkItems -Org $SourceOrg -Project $pr.repository.project.id -Username $sourceUsername -PAT $sourcePAT -RepoIdOrName $pr.repository.name -PullRequestId $pr.pullRequestId
      
      $sourcePRID = $pr.pullRequestId
      $sourcePRUrl = $pr.url
      $pr.PSObject.Properties.Remove('url')
      $pr.PSObject.Properties.Remove('_links')
      $pr.lastMergeCommit.PSObject.Properties.Remove('url')
      $pr.lastMergeTargetCommit.PSObject.Properties.Remove('url')
      $pr.lastMergeSourceCommit.PSObject.Properties.Remove('url')
      $pr.PSObject.Properties.Remove('pullRequestId')
      $pr.PSObject.Properties.Remove('codeReviewId')
      
      $targetRepo = GetRepo -Org $DestOrg -Project $destProject -Username $DestUsername -PAT $destPAT -repoName $pr.repository.name

      $pr.repository = $targetRepo

      $pr.mergeId = $targetMerge.mergeOperationId;

      $pr | Add-Member -MemberType NoteProperty -Name "workItemRefs" -Value @()

      foreach ($wi in $sourceWorkItems) {
        Write-Output "Fetching work item ref $($wi.id) on PR $($targetRepo.name)/$($sourcePRID)"
        $reflectedWi = GetWorkReflectedWorkItem -Org $destOrg -PAT $destPAT -Username $destUsername -WorkItemUrl $wi.url
        if ($null -ne $reflectedWi) {
          $pr.workItemRefs += $reflectedWi
          Write-Output "Attaching work item reference [$($reflectedWi.id)]."
        }
        else 
        {
          Write-Warning "Could not locate the referenced work item [$($wi.id)] in target org."
        }
      }

      Write-Output "Creating pull request $($targetRepo.name)/$($sourcePRID)"
      $targetPr = CreatePullRequest -Org $destOrg -Project $destProject -PAT $destPAT -Username $destUsername -PullRequest $pr -RepoId $targetRepo.id

      if ($null -eq $targetPr) {
        Write-Error "Failed to create pull request $($sourcePRID)!"
        continue
      }

      Write-Output "Pull request $sourcePRID -> $($targetPr.pullRequestId) has been created."

      if ($null -eq $sourceThreads) {
        $sourceThreads = @()
      }
      
      $sourceThreads += [PSCustomObject]@{
        "properties" = [PSCustomObject]@{
          "Microsoft.TeamFoundation.Discussion.SupportsMarkdown" = @{
              "`$type" = "System.Int32"
              "`$value" = 1
          }
          "Microsoft.TeamFoundation.Discussion.UniqueID" = @{
            "`$type" = "System.String"
            "`$value" = [System.Guid]::NewGuid().ToString()
          }
        }
        "status" = "closed"
        "comments" = @([PSCustomObject]@{
          "parentCommentId" = 0
          "commentType" = "system"
          "content" = "Pull request migrated from [PR $sourcePRID]($sourcePRUrl)."
        })
      }

      foreach ($thread in $sourceThreads) {
        Write-Output "Creating a pull request thread $($targetRepo.name)/$($sourcePRID)"
        $thread.PSObject.Properties.Remove('id')
        $thread.PSObject.Properties.Remove('url')
        $thread.PSObject.Properties.Remove('_links')
        $targetThread = CreatePullRequestThread -Org $destOrg -Project $destProject -PAT $destPAT -Username $destUsername -PullRequestThread $thread -RepoId $targetRepo.id -PullRequestId $targetPr.pullRequestId
      }
      
      Write-Output ""
    }
  } else {
    Write-Warning "No pull requests found in $sourceOrg/$sourceProject"
  }
}

Set-Location $PSScriptRoot
