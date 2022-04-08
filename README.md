# gha-k8s-toolbox
A Github Action for MobileCoin general kubernetes needs.

This is a bit of a dumping ground for scripts and automation around interacting with our Kubernetes clusters via Rancher, creating environments and deploying charts and manifests.


## Functions (`with.action:`)

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

### helm-s3-publish

Publish a helm chart to an s3 bucket.

⚠️ Note: Run these jobs with a concurrency of one. Running simultaneous uploads to an s3 bucket may cause chart index corruption.

```yaml
    - name: Package and publish chart
      uses: mobilecoinofficial/gha-k8s-toolbox@v1.0
      with:
        action: helm-s3-publish
        aws_access_key_id: ${{ secrets.CHARTS_AWS_ACCESS_KEY_ID }}
        aws_secret_access_key: ${{ secrets.CHARTS_AWS_SECRET_ACCESS_KEY }}
        aws_default_region: us-east-2
        chart_repo: s3://charts.mobilecoin.com
        chart_app_version: 0.0.0-dev
        chart_version: 0.0.0-dev
        chart_path: ./chart
```

| with | type | description |
| --- | --- | --- |
| `aws_access_key_id` | `string` | AWS Access Key ID for s3 bucket write |
| `aws_default_region` | `string` | AWS Region for s3 bucket |
| `aws_secret_access_key` | `string` | AWS Secret Access Key for s3 bucket write |
| `chart_repo` | `string` | `s3://` Url |
| `chart_app_version` | `string` | Chart App Version value |
| `chart_path` | `string` | relative path to chart templates |
| `chart_version` | `string` | Chart version value |

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

### pvcs-delete

Delete PersistentVolumeClaims in target namespace/cluster.

```yaml
    - name: Delete PersistentVolumeClaims
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

### sample-keys-create-secrets

Create `sample-keys-seeds` secret in target cluster/namespace.

⚠️ Note: Deletes existing secret before creating.

```yaml
    - name: Create wallet keys seed secrets
      uses: mobilecoinofficial/gha-k8s-toolbox@v1.0
      with:
        action: sample-keys-create-secrets
        fog_keys_seed: ${{ steps.seed.outputs.fog_keys_seed }}
        fog_report_signing_ca_cert: ${{ secrets.FOG_REPORT_SIGNING_CA_CERT }}
        initial_keys_seed: ${{ steps.seed.outputs.initial_keys_seed }}
        namespace: my-namespace
        rancher_cluster: ${{ secrets.RANCHER_CLUSTER }}
        rancher_url: ${{ secrets.RANCHER_URL }}
        rancher_token: ${{ secrets.RANCHER_TOKEN }}
```

| with | type | description |
| --- | --- | --- |
| `fog_keys_seed` | `string` | seed value for the Fog Keys |
| `fog_report_signing_ca_cert` | `string` | CA cert for fog report singing, used in Fog Keys generation |
| `initial_keys_seed` | `string` | seed value for the Initial Keys |
| `namespace` | `string` | Namespace in target cluster |
| `rancher_cluster` | `string` | Target cluster name |
| `rancher_url` | `string` | Rancher Server URL |
| `rancher_token` | `string` | Rancher API Token |


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
