# gha-k8s-toolbox
A Github Action for MobileCoin general kubernetes needs.

This is a bit of a dumping ground for scripts and automation around interacting with our Kubernetes clusters via Rancher, creating environments and deploying charts and manifests.


## Functions (`with.action:`)

### `generate-metadata`

Generate metadata from `env.GITHUB_*`

```yaml
    - name: Generate metadata
      id: metadata
      uses: mobilecoinofficial/gha-k8s-toolbox@v1
      with:
        action: generate-metadata
```

Outputs:
* `namespace`: k8s namespace derived from branch name
* `version`: base version
* `sha`: formatted commit SHA
* `tag`: Unique artifact tag. Use this to reference the Docker image
* `docker_tag`: Tags for the Docker image, in [docker/metadata-action syntax](https://github.com/docker/metadata-action#tags-input)

### fog-ingest-activate

Find toolbox pod and activate defined blue/green fog-ingest and retire the "flipside" fog-ingest (if exists).

```yaml
    - name: Activate primary ingest
      uses: mobilecoinofficial/gha-k8s-toolbox@v1.0
      with:
        action: fog-ingest-activate
        ingest_color: blue
        namespace: my-namespace
        rancher_cluster: ${{ secrets.RANCHER_CLUSTER }}
        rancher_url: ${{ secrets.RANCHER_URL }}
        rancher_token: ${{ secrets.RANCHER_TOKEN }}
```

| with | type | description |
| --- | --- | --- |
| `ingest_color` | `string` | blue or green |
| `namespace` | `string` | Namespace in target cluster |
| `rancher_cluster` | `string` | Target cluster name |
| `rancher_url` | `string` | Rancher Server URL |
| `rancher_token` | `string` | Rancher API Token |

### helm-deploy

Deploy helm chart in target namespace/cluster

```yaml
    - name: Deploy environment setup
      uses: mobilecoinofficial/gha-k8s-toolbox@v1.0
      with:
        action: helm-deploy
        chart_repo: https://s3.us-east-2.amazonaws.com/charts.mobilecoin.com/
        chart_name: mc-core-dev-env-setup
        chart_version: 0.0.0-dev
        chart_values: .tmp/values/mc-core-dev-env-values.yaml
        chart_set: |
          --set image.org=${{ inputs.docker_image_org }}
        release_name: mc-core-dev-env-setup
        namespace: my-namespace
        rancher_cluster: ${{ secrets.RANCHER_CLUSTER }}
        rancher_url: ${{ secrets.RANCHER_URL }}
        rancher_token: ${{ secrets.RANCHER_TOKEN }}
```

| with | type | description |
| --- | --- | --- |
| `chart_repo` | `string` | Public Chart Repo Url |
| `chart_name` | `string` | Name of chart in repo |
| `chart_set` | `\n delimitated list` | (optional) list of `--set` options for helm |
| `chart_timeout` | `duration` | (optional - default `10m`) Duration to wait for resources to become healthy |
| `chart_values` | `string` | (optional) Path to values.yaml file |
| `chart_version` | `string` | version of chart |
| `namespace` | `string` | Namespace in target cluster |
| `release_name` | `string` | Helm release name |
| `rancher_cluster` | `string` | Target cluster name |
| `rancher_url` | `string` | Rancher Server URL |
| `rancher_token` | `string` | Rancher API Token |

### helm-release-delete

Delete a helm release in the target namespace/cluster.

```yaml
    - name: Delete release
      uses: mobilecoinofficial/gha-k8s-toolbox@v1.0
      with:
        action: helm-release-delete
        namespace: my-namespace
        release_name: consensus-node-1
        rancher_cluster: ${{ secrets.RANCHER_CLUSTER }}
        rancher_url: ${{ secrets.RANCHER_URL }}
        rancher_token: ${{ secrets.RANCHER_TOKEN }}
```

| with | type | description |
| --- | --- | --- |
| `namespace` | `string` | Namespace in target cluster |
| `release_name` | `string` | Helm release name |
| `rancher_cluster` | `string` | Target cluster name |
| `rancher_url` | `string` | Rancher Server URL |
| `rancher_token` | `string` | Rancher API Token |

### helm-publish

Publish a helm chart to a harbor repo.

```yaml
    - name: Publish chart
      uses: mobilecoinofficial/gha-k8s-toolbox@v1
      with:
        action: helm-publish
        chart_repo_username: ${{ secrets.HARBOR_USERNAME }}
        chart_repo_password: ${{ secrets.HARBOR_PASSWORD }}
        chart_repo: ${{ env.CHART_REPO }}
        chart_app_version: ${{ needs.generate-metadata.outputs.tag }}
        chart_version: ${{ needs.generate-metadata.outputs.tag }}
        chart_path: .internal-ci/helm/${{ matrix.chart }}
```

| with | type | description |
| --- | --- | --- |
| `namespace` | `string` | Namespace in target cluster |
| `chart_repo_username` | `string` | Harbor user with write access |
| `chart_repo_password` | `string` | Harbor user with write access |
| `chart_repo` | `string` | Public Chart Repo Url |
| `chart_app_version` | `string` | App version |
| `chart_version` | `string` | Chart version |
| `chart_path` | `string` | Path to chart files in the repo |

### namespace-delete

Delete a namespace in the target Rancher/K8s cluster.

```yaml
    - name: Delete Namespace
      uses: mobilecoinofficial/gha-k8s-toolbox@v1.0
      with:
        action: namespace-delete
        namespace: my-namespace
        rancher_cluster: ${{ secrets.RANCHER_CLUSTER }}
        rancher_url: ${{ secrets.RANCHER_URL }}
        rancher_token: ${{ secrets.RANCHER_TOKEN }}
```

| with | type | description |
| --- | --- | --- |
| `` | `` |  |
| `namespace` | `string` | Namespace in target cluster |
| `rancher_cluster` | `string` | Target cluster name |
| `rancher_url` | `string` | Rancher Server URL |
| `rancher_token` | `string` | Rancher API Token |

### namespace-create

Create a namespace and add it to the Default project in the target Rancher/K8s cluster.

```yaml
    - name: Create Namespace
      uses: mobilecoinofficial/gha-k8s-toolbox@v1.0
      with:
        action: namespace-create
        namespace: my-namespace
        rancher_cluster: ${{ secrets.RANCHER_CLUSTER }}
        rancher_url: ${{ secrets.RANCHER_URL }}
        rancher_token: ${{ secrets.RANCHER_TOKEN }}
```

| with | type | description |
| --- | --- | --- |
| `namespace` | `string` | Namespace in target cluster |
| `rancher_cluster` | `string` | Target cluster name |
| `rancher_url` | `string` | Rancher Server URL |
| `rancher_token` | `string` | Rancher API Token |

### pod-restart

Restart pods by scaling the Deployment/StatefulSet to 0 and back to original scale.

```yaml
    - name: Restart Consensus Nodes
      uses: mobilecoinofficial/gha-k8s-toolbox@v1.0
      with:
        action: pod-restart
        namespace: my-namespace
        object_name: deployment.app/consensus-node-1
        rancher_cluster: ${{ secrets.RANCHER_CLUSTER }}
        rancher_url: ${{ secrets.RANCHER_URL }}
        rancher_token: ${{ secrets.RANCHER_TOKEN }}
```

| with | type | description |
| --- | --- | --- |
| `object_name` | `string` | Object to scale (app.deployment, app.scaleset)
| `namespace` | `string` | Namespace in target cluster |
| `rancher_cluster` | `string` | Target cluster name |
| `rancher_url` | `string` | Rancher Server URL |
| `rancher_token` | `string` | Rancher API Token |

### pvc-delete

Delete a single PersistentVolumeClaims in target namespace/cluster.

```yaml
    - name: Delete single PVC
      uses: mobilecoinofficial/gha-k8s-toolbox@v1.0
      with:
        action: pvc-delete
        namespace: my-namespace
        object_name: my-pvc-0
        rancher_cluster: ${{ secrets.RANCHER_CLUSTER }}
        rancher_url: ${{ secrets.RANCHER_URL }}
        rancher_token: ${{ secrets.RANCHER_TOKEN }}
```

| with | type | description |
| --- | --- | --- |
| `namespace` | `string` | Namespace in target cluster |
| `object_name` | `string` | PVC in target namespace |
| `rancher_cluster` | `string` | Target cluster name |
| `rancher_url` | `string` | Rancher Server URL |
| `rancher_token` | `string` | Rancher API Token |

### pvcs-delete

Delete all PersistentVolumeClaims in target namespace/cluster.

```yaml
    - name: Delete all PersistentVolumeClaims
      uses: mobilecoinofficial/gha-k8s-toolbox@v1.0
      with:
        action: pvcs-delete
        namespace: my-namespace
        rancher_cluster: ${{ secrets.RANCHER_CLUSTER }}
        rancher_url: ${{ secrets.RANCHER_URL }}
        rancher_token: ${{ secrets.RANCHER_TOKEN }}
```

| with | type | description |
| --- | --- | --- |
| `namespace` | `string` | Namespace in target cluster |
| `rancher_cluster` | `string` | Target cluster name |
| `rancher_url` | `string` | Rancher Server URL |
| `rancher_token` | `string` | Rancher API Token |

### secrets-create-from-file

Create a k8s secret from a file/directory.  Will delete the existing secret and recreate.

```yaml
    - name: Create wallet key secrets
      uses: mobilecoinofficial/gha-k8s-toolbox@v1
      with:
        action: secrets-create-from-file
        namespace: ${{ inputs.namespace }}
        rancher_cluster: ${{ secrets.RANCHER_CLUSTER }}
        rancher_url: ${{ secrets.RANCHER_URL }}
        rancher_token: ${{ secrets.RANCHER_TOKEN }}
        object_name: some-secret
        src: .tmp/some-secret
```

| with | type | description |
| --- | --- | --- |
| `namespace` | `string` | Namespace in target cluster |
| `rancher_cluster` | `string` | Target cluster name |
| `rancher_url` | `string` | Rancher Server URL |
| `rancher_token` | `string` | Rancher API Token |
| `object_name` | `string` | K8s object to create |
| `src` | `string` | File/Directory to make into the secret |

### configmap-create-from-file

Create a k8s configmap from a file/directory.  Will delete existing CM and recreate.

```yaml
    - name: Create wallet key secrets
      uses: mobilecoinofficial/gha-k8s-toolbox@v1
      with:
        action: configmap-create-from-file
        namespace: ${{ inputs.namespace }}
        rancher_cluster: ${{ secrets.RANCHER_CLUSTER }}
        rancher_url: ${{ secrets.RANCHER_URL }}
        rancher_token: ${{ secrets.RANCHER_TOKEN }}
        object_name: some-configmap
        src: .tmp/some-configmap
```

| with | type | description |
| --- | --- | --- |
| `namespace` | `string` | Namespace in target cluster |
| `rancher_cluster` | `string` | Target cluster name |
| `rancher_url` | `string` | Rancher Server URL |
| `rancher_token` | `string` | Rancher API Token |
| `object_name` | `string` | K8s object to create |
| `src` | `string` | File/Directory to make into the configmap |


### toolbox-copy

Copy a file to the blue/green fog-ingest toolbox pod.

```yaml
    - name: Copy Fog Report Authority root CA cert to toolbox
      uses: mobilecoinofficial/gha-k8s-toolbox@v1.0
      with:
        action: toolbox-copy
        ingest_color: blue
        namespace: my-namespace
        rancher_cluster: ${{ secrets.RANCHER_CLUSTER }}
        rancher_url: ${{ secrets.RANCHER_URL }}
        rancher_token: ${{ secrets.RANCHER_TOKEN }}
        src: ${{ env.FOG_REPORT_SIGNING_CA_CERT_PATH }}
        dst: /tmp/fog_report_signing_ca_cert.pem
```

| with | type | description |
| --- | --- | --- |
| `ingest_color` | `string` | blue or green |
| `command` | `string` | command to run on the toolbox pod |
| `namespace` | `string` | Namespace in target cluster |
| `rancher_cluster` | `string` | Target cluster name |
| `rancher_url` | `string` | Rancher Server URL |
| `rancher_token` | `string` | Rancher API Token |
| `src` | `string` | source in action context |
| `dst` | `string` | destination in toolbox pod |

### kubectl-exec

Run commands that have access to the specified rancher cluster

```yaml
    - name: Run kubectl diff to output diff
      uses: mobilecoinofficial/gha-k8s-toolbox@v1.0
      with:
        action: kubectl-exec
        rancher_cluster: ${{ secrets.RANCHER_CLUSTER }}
        rancher_url: ${{ secrets.RANCHER_URL }}
        rancher_token: ${{ secrets.RANCHER_TOKEN }}
        command: |
          helm template . | k diff -f -
```

| with | type | description |
| --- | --- | --- |
| `command` | `string` | command to run on the toolbox pod |
| `rancher_cluster` | `string` | Target cluster name |
| `rancher_url` | `string` | Rancher Server URL |
| `rancher_token` | `string` | Rancher API Token |

### toolbox-exec

Run a command on the blue/green fog-ingest toolbox pod.

```yaml
    - name: Run fog-recovery database migrations
      uses: mobilecoinofficial/gha-k8s-toolbox@v1.0
      with:
        action: toolbox-exec
        ingest_color: blue
        namespace: my-namespace
        rancher_cluster: ${{ secrets.RANCHER_CLUSTER }}
        rancher_url: ${{ secrets.RANCHER_URL }}
        rancher_token: ${{ secrets.RANCHER_TOKEN }}
        command: |
          /usr/local/bin/fog-sql-recovery-db-migrations
```

| with | type | description |
| --- | --- | --- |
| `ingest_color` | `string` | blue or green |
| `command` | `string` | command to run on the toolbox pod |
| `namespace` | `string` | Namespace in target cluster |
| `rancher_cluster` | `string` | Target cluster name |
| `rancher_url` | `string` | Rancher Server URL |
| `rancher_token` | `string` | Rancher API Token |

## Build and CI

⚠️ Remember to update `action.yaml` image version if bumping the `major` or `minor` numbers.

This repo will automatically bump the patch version, tag and create a release on push to main. Add `#major`, `#minor` to the commit message to create major/minor releases.

- https://github.com/marketplace/actions/github-tag-bump
- https://github.com/marketplace/actions/gh-release
