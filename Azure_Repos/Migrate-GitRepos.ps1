param(
  [Parameter(mandatory=$true)][String]$sourceOrg,
  [Parameter(mandatory=$true)][String]$sourceProject,
  [Parameter(mandatory=$true)][String]$sourceUsername,
  [Parameter(mandatory=$true)][String]$sourcePAT,
  [Parameter(mandatory=$false)][String]$destOrg,
  [Parameter(mandatory=$true)][String]$destProject,
  [Parameter(mandatory=$false)][String]$destPAT,
  [Parameter(mandatory=$false)][String]$destUsername,
  [switch]$clean,
  [switch]$cloneRepos,
  [switch]$createRemotes,
  [switch]$createForks,
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
    return Invoke-WebRequest "${FinalOrgBase}/_apis/${Function}?${queryString}api-version=${APIVersion}" -UseBasicParsing -Headers $Headers -Method GET -Body $Body -ContentType $ContentType
  }

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

function GetRepoId {
  param (
    [Parameter(mandatory=$true)][String]$Org,
    [Parameter(mandatory=$true)][String]$Project,
    [Parameter(mandatory=$true)][String]$Username,
    [Parameter(mandatory=$true)][String]$PAT,
    [Parameter(mandatory=$true)][String]$repoName
  )

  $parameters = @{includeParent="false"}
  $response = Invoke-AzureDevOpsAPI -Org $Org -Project $Project -Function "git/repositories/${repoName}" -Parameters $parameters -Username $Username -PAT $PAT | ConvertFrom-Json
  return $response.id
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

Set-Location $PSScriptRoot
