# Azure Repo Migration

This document details how to migrate git repositories from one Azure DevOps Project to another. This can be done across different Azure DevOps Organisations and also includes the wikis (Which are backed by a hidden git repository)

## Prerequisites

* You will need a PAT Token with relevant permissions on both the source and destination organisations / projects.

* You will need the [New Project Script][New_Project_Script] to create the destination project.

* You will need the [Migrate Git Repos Script][Migrate_Git_Repos_Script] to migrate the git repositories to the destination project.

* You will need the [Migrate Git Repos Task Group][Migrate_Git_Repos_Task_Group] to create a release pipeline that will migrate the git repositories to the destination project.

* Although this can be ran locally, I recommend running this as an Azure DevOps Release Pipeline. To do so, you will need permissions to be able to create a Release Pipeline and required variables.

## Walkthrough

1. First you need to import the [Migrate Git Repos task group][Migrate_Git_Repos_Task_Group] - Go to Pipelines -> Task Groups -> Import a task group -> Save (You will need to have the task group on your local machine)

It automatically adds `- Copy` to the name, I recommend you remove this.

2. Create a Release Pipeline (For this demo we are using the GUI but it could also be completed in YAML). To do this go to Pipelines -> Releases -> New Pipeline

You will be prompted to select a template, just select `Empty Job` and remember to name your Pipeline

3. Click on `Add an Artifact` then select the project and repo that contains the `New Project` and `Migrate Git Repos` scripts. Set the default branch to `main` and the source alias to `GitMigration`. Finally click `Add`

4. Rename `Stage 1` to the name of the project you are migrating.

5. Click on tasks for the first stage. On `Agent Job` the Agent Pool should be set to `Hosted Azure Pipelines` and Agent Specification should be `vs2017-win2016`. On `Agent Job` click on the `+` sign to add the task group to this agent job. You can search for `Migrate Git Repos`. (If it doesn't appear try refreshing your browser)

It automatically adds `$(Description)` to the display name, I recommend you remove this.

6. Click on variables and add the following Pipeline Variables:

| Name            | Value                                                | Scope          |
| :-----------    | :-----------                                         | :-----------   |
| Description     | Enter Description of new project (If blank use "")   | Stage          |
| destOrg         | Enter Destination Organisation Name                  | Release        |
| destPAT         | Enter Destination PAT (Mark variable as secret)      | Release        |
| destProject     | Enter Destination Project name                       | Stage          |
| destUsername    | Enter Destination User name (name@orgname.com) | Release        |
| ProcessTemplate | Enter Process Template (Agile, Scrum or CMMI)        | Stage          |
| sourceOrg       | Enter Source Organisation Name                       | Stage          |
| sourcePAT       | Enter Source PAT (Mark variable as secret)           | Stage          |
| sourceProject   | Enter Source Project name                            | Stage          |
| sourceUsername  | Enter Source User name (name@orgname.com)      | Release        |
| VersionControl  | Enter Version Control (GIT)                          | Release        |
| Visibility      | Enter Visibility (private, public)                   | Stage          |


7. This is now ready to migrate Git repositories from one project to another. Click Create Release and let it run. During testing this usually takes sub 40 seconds per project.

8. You can migrate multiple project Git repositories by simply cloning your first stage. You just need to rename your additional stages as per step 4 above and amend the variable values pertaining to these additional stages.

9. Once the migration is complete, you need to manually point the new project Wiki at the underlying Git repo. Overview -> Wiki -> Publish code as wiki

Set the Repository and the folder to the correct values. Enter a Wiki name and click publish.

10. You will now need to configure any relevant Policies and Permissions

[New_Project_Script]: https://github.com/ghostinthewires/azure-repo-migrator/blob/main/Azure_Repos/New-Project.ps1

[Migrate_Git_Repos_Script]: https://github.com/ghostinthewires/azure-repo-migrator/blob/main/Azure_Repos/Migrate-GitRepos.ps1

[Migrate_Git_Repos_Task_Group]: https://github.com/ghostinthewires/azure-repo-migrator/blob/main/Azure_Repos/Migrate%20Git%20Repos.json
