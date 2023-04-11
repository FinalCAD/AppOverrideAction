# AppOverrideAction

Github Action to apply an override on eks-apps repository to deploy application with parameters.
Override file is in yaml, by default file is '.finalcad/overrides.yaml'.
This file must validate against `cue` schema.
This action only update `eks-apps` repo, argocd will deploy this app with any override.

## Allowed values for override

You can check every allowed values on this [page](https://finalcad.atlassian.net/wiki/spaces/INFRA/pages/3752656915/Override+parameters)

## Inputs
### `app-name`
[**Required**] Application ID to identify the apps in eks-apps

### `debug`
Debug mode (will not update eks-apps repository), Default: false

### `helm-repo`
Repository for eks-apps, Default: `FinalCAD/eks-apps(-sandbox)`

### `helm-red`
Reference to use for `helm-repo`, Default: master

### `gitub-token`
Github token to avoid limit rate when pulling package

### `github-ssh`
[**Required**] Github ssh key to pull `eks-apps` repository

### `environment`
Finalcad envrionment: production, staging, sandbox

### `regions`
Finalcad region list, Default: `eu,ap`

### `override-file`
Path for override file, Default: `.finalcad/overrides.yaml`

### `kubernetes-version`
List of kubernetes version to test tthe chart against, default: `1.23.0,1.24.0`

## Usage

```yaml
- name: Push secrets
  uses: FinalCAD/AppOverrideAction@v0.0.1
  with:
    github-ssh: ${{ secrets.GH_DEPLOY_SSH }}
    environment: sandbox
    regions: eu,ap
    app-name: api1-service-api
```
