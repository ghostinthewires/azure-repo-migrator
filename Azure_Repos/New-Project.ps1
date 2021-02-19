param
(
    [Parameter(Mandatory=$true)][String]$destPAT,
    [Parameter(Mandatory=$true, HelpMessage="Specify an Azure Devops Organisation, example: 'devopsgroup'")]$destOrg,
    [Parameter(Mandatory=$true, HelpMessage="Specify a valid version control, example: 'TFS' or 'GIT'")][ValidateSet("TFS", "GIT")]$VersionControl,
    [Parameter(Mandatory=$true, HelpMessage="Specify a Project Name, example: 'DOG Test Project 1'")]$destProject,
    [Parameter(Mandatory=$true, HelpMessage="Specify a Project Visibility, example: 'private' or 'public'")][ValidateSet("private", "public")]$Visibility,
    [Parameter(Mandatory=$true, HelpMessage="Specify a Project Decription, example: 'This project is used for coding stuff'")]$Description,
    [Parameter(Mandatory=$true, HelpMessage="Specify a Process Template, example: 'Agile', 'Scrum' or 'CMMI'")][ValidateSet("Agile", "Scrum", "CMMI")]$ProcessTemplate

)

$APIVersion = "5.0"
Function New-AzDevOpsAuth
{

        # Base64-encodes the Personal Access Token (PAT) appropriately
        $script:base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{0}" -f $destPAT)))
}

Function Get-AzDevOpsProject
{
    Try
    {

    #Construct the URI for the JSON.
    $URI = ("https://dev.azure.com/" + $destOrg + "/" + "_apis/projects" + "/" + $destProject + "?api-version=" + $APIVersion + "&includeCapabilities=true");

    #Execute the invoke rest API.
    $webResponse = Invoke-RestMethod -Method Get -uri ($URI) -Headers @{
        Authorization = ("Basic {0}" -f $base64AuthInfo)
       } -ContentType "application/json";
}
Catch
{
    if ($_.Exception.Response.StatusCode.value__ -ne "200") {
        New-AzDevOpsProject
    } else {
        ""
    }
}
}

Function New-AzDevOpsProject
{

    Try
    {



    #Set the correct template ID.
    Switch($ProcessTemplate)
    {
        "Agile" {$TemplateID = "adcc42ab-9882-485e-a3ed-7678f01f66bc"}
        "Scrum" {$TemplateID = "6b724908-ef14-45cf-84f8-768b5384da45"}
        "CMMI" {$TemplateID = "27450541-8e31-4150-9947-dc59f998fc01"}
    }

    #Set the correct VCS ID.
    Switch($VersionControl)
    {
        "TFS" {$VersionControlID = "Tfvc"}
        "GIT" {$VersionControlID = "Git"}
    }

    #Construct the URI for the JSON.
    $URI = ("https://dev.azure.com/" + $destOrg + "/" + "_apis/projects?api-version=" + $APIVersion);



    #Construct the JSON.
    $Body = @{
            name = "$destProject"
            description = "$Description"
            visibility = "$Visibility"
            capabilities = @{
                versioncontrol = @{
                    sourceControlType = "$VersionControlID"
                }
                processTemplate = @{
                    templateTypeId = "$TemplateID"
                }
            }
        } | ConvertTo-Json

    #Execute the invoke rest API.
    Invoke-RestMethod -Method Post -uri ($URI) -Headers @{
        Authorization = ("Basic {0}" -f $base64AuthInfo)
       } -Body ($Body) -ContentType "application/json";
}
Catch
{
    #Information to be added to private comment in ticket when unknown error occurs
    $ErrMsg = "Powershell exception :: Line# $($_.InvocationInfo.ScriptLineNumber) :: $($_.Exception.Message)"
    Write-Output "Script failed to run"
    Write-Output $ErrMsg

}
}

#Call the function.
New-AzDevOpsAuth
Get-AzDevOpsProject
