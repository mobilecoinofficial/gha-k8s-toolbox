#!/bin/bash
# Copyright (c) 2022 MobileCoin Inc.

set -o errexit
set -o pipefail
shopt -s expand_aliases

export KUBECONFIG="/opt/.kube/config"
mkdir -p /opt/.kube/cache
touch "${KUBECONFIG}"
chmod 600 "${KUBECONFIG}"
alias k="kubectl --cache-dir /opt/.kube/cache"

error_exit()
{
    msg="${1}"

    echo "${msg}" 1>&2
    exit 1
}

echo_exit()
{
    msg="${1}"

    echo "${msg}"
    exit 0
}

is_set()
{
    var_name="${1}"

    if [ -z "${!var_name}" ]; then
        error_exit "${var_name} is not set."
    fi
}

rancher_get_kubeconfig()
{
    is_set INPUT_RANCHER_URL
    is_set INPUT_RANCHER_TOKEN
    is_set INPUT_RANCHER_CLUSTER

    echo "-- Get kubeconfig for ${INPUT_RANCHER_CLUSTER} ${INPUT_RANCHER_URL}"
    auth_header="Authorization: Bearer ${INPUT_RANCHER_TOKEN}"
    kubeconfig_url=$(curl --retry 5 -sSLf -H "${auth_header}" "${INPUT_RANCHER_URL}/v3/clusters/?name=${INPUT_RANCHER_CLUSTER}" | jq -r .data[0].actions.generateKubeconfig)

    echo "-- Write kubeconfig"
    curl --retry 5 -sSLf -H "${auth_header}" -X POST "${kubeconfig_url}" | jq -r .config > "${KUBECONFIG}"
    chmod 600 "${KUBECONFIG}"
}

helm_upgrade()
{
    repo_name="${1}"
    sets="${2}"

    for t in {1..3}
    do
        echo "-- Deploy ${INPUT_CHART_NAME} - try ${t}"
        # shellcheck disable=SC2086
        if helm upgrade "${INPUT_RELEASE_NAME}" "${repo_name}/${INPUT_CHART_NAME}" \
            -i --wait --timeout="${INPUT_CHART_WAIT_TIMEOUT}" \
            --namespace "${INPUT_NAMESPACE}" \
            --reset-values \
            --version "${INPUT_CHART_VERSION}" ${sets}
        then
            echo_exit "Deploy Successful"
        else
            sleep 10
        fi
    done
    error_exit "Helm Deployment Failed"
}

helm_upgrade_with_values()
{
    repo_name="${1}"
    sets="${2}"

    for t in {1..3}
    do
        echo "-- deploy ${INPUT_CHART_NAME} with values - try ${t}"
        # shellcheck disable=SC2086
        if helm upgrade "${INPUT_RELEASE_NAME}" "${repo_name}/${INPUT_CHART_NAME}" \
            -i --wait --timeout="${INPUT_CHART_WAIT_TIMEOUT}" \
            -f "${INPUT_CHART_VALUES}" \
            --namespace "${INPUT_NAMESPACE}" \
            --reset-values \
            --version "${INPUT_CHART_VERSION}" ${sets}
        then
            echo_exit "Deploy Successful"
        else
            sleep 10
        fi
    done
    error_exit "Helm Deployment Failed"
}

toolbox_cmd()
{
    pod="${1}"
    command="${2}"

    k exec -n "${INPUT_NAMESPACE}" "${pod}" -c toolbox -- /bin/bash -c "${command}"
}

if [ -n "${INPUT_ACTION}" ]
then
    case "${INPUT_ACTION}" in
        fog-ingest-activate)
            # CBB: we do a lot of copy pasta for "standard" commands, we should make functions.
            # Activate target blue/green fog-ingest. Retire flipside ingest if it exists.
            rancher_get_kubeconfig
            is_set INPUT_NAMESPACE
            is_set INPUT_INGEST_COLOR

            declare -A peer_keys
            active_found="no"
            retired="no"

            if [ "${INPUT_INGEST_COLOR}" == "blue" ]
            then
                flipside="green"
            else
                flipside="blue"
            fi

            instance="fog-ingest-${INPUT_INGEST_COLOR}"
            peers=("${instance}-0.${instance}" "${instance}-1.${instance}")

            flipside_instance="fog-ingest-${flipside}"
            flipside_peers=("${flipside_instance}-0.${flipside_instance}" "${flipside_instance}-1.${flipside_instance}")

            echo "-- Primary Peers: ${INPUT_INGEST_COLOR} ${peers[*]}"
            echo "-- Flipside Peers: ${flipside} ${flipside_peers[*]}"

            echo "-- Get toolbox pod"
            toolbox=$(k get pods -n "${INPUT_NAMESPACE}" -l "app.kubernetes.io/instance=${instance},app=toolbox" -o=name | sed -r 's/pod\///')

            echo "-- Check for flipside ingest"
            flipside_pods=$(k get pods -n "${INPUT_NAMESPACE}" -l "app.kubernetes.io/instance=${flipside_instance},app=fog-ingest" -o=name | sed -r 's/pod\///')

            if [ -n "${flipside_pods}" ]
            then
                active_found=""
                echo "-- Looking for Active flipside ingest"
                for p in "${flipside_peers[@]}"
                do
                    echo "--- checking insecure-fog-ingest://${p}:3226"
                    command="RUST_LOG=error fog_ingest_client --uri 'insecure-fog-ingest://${p}:3226' get-status"
                    result=$(toolbox_cmd "${toolbox}" "${command}")
                    echo "${result}" | jq -r .
                    mode=$(echo "${result}" | jq -r .mode)

                    if [ "${mode}" == "Active" ]
                    then
                        echo "-- ${p} Active ingest found, retiring."
                        command="RUST_LOG=error fog_ingest_client --uri 'insecure-fog-ingest://${p}:3226' retire | jq -r ."
                        toolbox_cmd "${toolbox}" "${command}"
                        active_found="yes"
                        retired="yes"
                    fi
                done

                if [ "${active_found}" != "yes" ]
                then
                    echo "-- No active flipside ingest found."
                fi
            else
                echo "-- No flipside ingest found."
            fi

            echo "-- Check Primary for active ingest"
            for p in "${peers[@]}"
            do
                echo "--- checking insecure-fog-ingest://${p}:3226"
                command="RUST_LOG=error fog_ingest_client --uri 'insecure-fog-ingest://${p}:3226' get-status"
                result=$(toolbox_cmd "${toolbox}" "${command}")
                echo "${result}" | jq -r .
                mode=$(echo "${result}" | jq -r .mode)
                peer_keys[${p}]=$(echo "${result}" | jq -r .ingress_pubkey)

                if [ "${mode}" == "Active" ]
                then
                    echo_exit "-- Active ingest found, no action needed."
                fi
            done

            # We can run into a lost keys issue by not checking for an "active" key that isn't on an active ingest.
            #  use get-ingress-public-key-records to list keys and activate matching key if one exists.

            # does fog_ingest_client have get-ingress-public-key-records
            command="fog_ingest_client --help | grep get-ingress-public-key-records"
            if toolbox_cmd "${toolbox}" "${command}"
            then
                echo "-- checking for existing key records"
                command="RUST_LOG=error fog_ingest_client --uri 'insecure-fog-ingest://${instance}-0.${instance}:3226' get-ingress-public-key-records"
                result=$(toolbox_cmd "${toolbox}" "${command}")
                echo "${result}"

                key_records=$(echo "${result}" | jq -r '.[] | .ingress_public_key')

                if [[ -n "${key_records}" ]]
                then
                    for pk in ${key_records}
                    do
                        # if there are records list check against the keys on the current primary nodes
                        for peer in "${!peer_keys[@]}"
                        do
                            # if the keys match, then activate.
                            if [[ "${pk}" == "${peer_keys[${peer}]}" ]]
                            then
                                echo "-- Found active key on ${peer} - activating now."
                                command="RUST_LOG=error fog_ingest_client --uri 'insecure-fog-ingest://${peer}:3226' activate | jq -r ."
                                toolbox_cmd "${toolbox}" "${command}"

                                exit 0
                            fi
                        done
                    done

                    echo "-- Houston we have a problem. We have active keys that don't match any running ingest servers."
                    exit 1

                else
                    echo "-- no key records found (this is good)"
                fi
            fi

            echo "-- No Active Primary ingest found. Activating ingest 0."
            command="RUST_LOG=error fog_ingest_client --uri 'insecure-fog-ingest://${instance}-0.${instance}:3226' activate | jq -r ."
            toolbox_cmd "${toolbox}" "${command}"


            if [[ "${retired}" == "yes" ]]
            then
                echo "-- Progress block chain to finish ${flipside} retirement"
                # what do we need at this point?
                # if we made it here we have already run fog-distribution
                # generate keys
                #
                # fog-test-client
                echo "  -- Generate keys from seeds"
                command="INITIALIZE_LEDGER='true' FOG_REPORT_URL='fog://fog.${INPUT_NAMESPACE}.development.mobilecoin.com:443' /util/generate_origin_data.sh"
                toolbox_cmd "${toolbox}" "${command}"

                echo "  -- Use mobilecoind to generate blocks to finish retire of ${flipside}"
                command="/test/mobilecoind-integration-test.sh"
                toolbox_cmd "${toolbox}" "${command}"

                # check active/retired status, if both nodes are not idle we error out.
                echo "  -- Check ingest status to see if we made it to retired"
                for p in "${flipside_peers[@]}"
                do
                    echo "  -- checking insecure-fog-ingest://${p}:3226"
                    command="RUST_LOG=error fog_ingest_client --uri 'insecure-fog-ingest://${p}:3226' get-status"
                    result=$(toolbox_cmd "${toolbox}" "${command}")
                    echo "${result}" | jq -r .
                    mode=$(echo "${result}" | jq -r .mode)
                    if [[ "${mode}" == "Active" ]]
                    then
                        echo "-- ERROR: Oh No, ${p} is still Active, this node should have transitioned to Idle"
                        exit 1
                    fi
                done
                echo "-- ${flipside} ingest successfully retired"
            fi
            ;;

        helm-deploy)
            # Deploy a helm chart
            rancher_get_kubeconfig
            is_set INPUT_NAMESPACE
            is_set INPUT_RELEASE_NAME
            is_set INPUT_CHART_VERSION
            is_set INPUT_CHART_NAME
            is_set INPUT_CHART_WAIT_TIMEOUT

            echo "-- Add chart repo ${INPUT_CHART_REPO}"

            # log into chart repo with creds if provided.
            if [[ -n "${INPUT_CHART_REPO_USERNAME}" ]] && [[ -n "${INPUT_CHART_REPO_PASSWORD}" ]]
            then
                helm repo add repo "${INPUT_CHART_REPO}" \
                  --username "${INPUT_CHART_REPO_USERNAME}" \
                  --password "${INPUT_CHART_REPO_PASSWORD}"
            else
                helm repo add repo "${INPUT_CHART_REPO}"
            fi

            helm repo update

            set_options=$(echo -n "${INPUT_CHART_SET}" | tr '\n' ' ')

            if [ -n "${INPUT_CHART_VALUES}" ]
            then
                helm_upgrade_with_values repo "${set_options}"
            else
                helm_upgrade repo "${set_options}"
            fi
            ;;

        helm-release-delete)
            # Delete a helm release
            rancher_get_kubeconfig
            is_set INPUT_NAMESPACE
            is_set INPUT_RELEASE_NAME

            k get ns "${INPUT_NAMESPACE}" || echo_exit "Namespace doesn't exist"

            echo "-- Get release list"
            release=$(helm list -a -q -n "${INPUT_NAMESPACE}" | grep "${INPUT_RELEASE_NAME}" || true)
            if [ -n "${release}" ]
            then
                echo "-- Deleting release ${INPUT_RELEASE_NAME}"
                helm delete "${INPUT_RELEASE_NAME}" -n "${INPUT_NAMESPACE}" --wait --timeout="${INPUT_CHART_WAIT_TIMEOUT}"

                # Wait for delete since it seems like the helm chart sometimes doesn't really wait.
                echo "-- No for reals, wait for resources to delete"
                sleep 5
                k -n "${INPUT_NAMESPACE}" wait all --for=delete --timeout="${INPUT_CHART_WAIT_TIMEOUT}" -l "app.kubernetes.io/managed-by=Helm,app.kubernetes.io/instance=${INPUT_RELEASE_NAME}"

            else
                echo "-- Release ${INPUT_RELEASE_NAME} not found."
            fi
            ;;

        helm-publish)
            is_set INPUT_CHART_APP_VERSION
            is_set INPUT_CHART_PATH
            is_set INPUT_CHART_VERSION
            is_set INPUT_CHART_REPO
            is_set INPUT_CHART_REPO_PASSWORD
            is_set INPUT_CHART_REPO_USERNAME

            if [ "${INPUT_CHART_SIGN}" == "true" ]
            then
                is_set INPUT_CHART_PGP_KEYRING_PATH
                is_set INPUT_CHART_PGP_KEY_NAME
            fi

            echo "-- Create chart tmp dir - .tmp/charts"
            mkdir -p ".tmp/charts"

            echo "-- Updating chart dependencies"
            helm dependency update "${INPUT_CHART_PATH}"

            if [ "${INPUT_CHART_SIGN}" == "true" ]
            then
                echo "-- Package and sign chart with provided pgp key"
                helm package "${INPUT_CHART_PATH}" \
                    -d ".tmp/charts" \
                    --app-version="${CHART_APP_VERSION}" \
                    --version="${INPUT_CHART_VERSION}" \
                    --sign \
                    --keyring="${INPUT_CHART_PGP_KEYRING_PATH}" \
                    --key="${INPUT_CHART_PGP_KEY}"
            else
                echo "-- Package unsigned chart"
                helm package "${INPUT_CHART_PATH}" \
                    -d ".tmp/charts" \
                    --app-version="${INPUT_CHART_APP_VERSION}" \
                    --version="${INPUT_CHART_VERSION}"
            fi

            echo "-- Add chart repo ${INPUT_CHART_REPO}"
            helm repo add repo "${INPUT_CHART_REPO}" \
                --username "${INPUT_CHART_REPO_USERNAME}" \
                --password "${INPUT_CHART_REPO_PASSWORD}"

            echo "-- Push chart"
            chart_name=$(basename "${INPUT_CHART_PATH}")
            helm cm-push --force ".tmp/charts/${chart_name}-${INPUT_CHART_VERSION}.tgz" repo
            ;;

        namespace-delete)
            # Delete namespace in target cluster.
            rancher_get_kubeconfig
            is_set INPUT_NAMESPACE

            echo "-- Deleting ${INPUT_NAMESPACE} namespace from ${INPUT_RANCHER_CLUSTER}"
            k delete ns "${INPUT_NAMESPACE}" --now --wait --request-timeout=5m --ignore-not-found
            ;;

        namespace-create)
            # Create a namespace in the default project so we get all the default configs and secrets
            rancher_get_kubeconfig
            is_set INPUT_NAMESPACE
            is_set INPUT_RANCHER_PROJECT

            echo "-- Create namespace ${INPUT_NAMESPACE}"
            # Don't sweat it if the namespace already exists.
            if k create ns "${INPUT_NAMESPACE}"
            then
                echo "Namespace created"
            else
                echo "Namespace already exists"
                exit 0
            fi

            auth_header="Authorization: Bearer ${INPUT_RANCHER_TOKEN}"

            # Add namespace to Default project
            # Get cluster data and resource links
            echo "-- Query Rancher for cluster info"
            cluster=$(curl --retry 5 -sSLf -H "${auth_header}" "${INPUT_RANCHER_URL}/v3/clusters/?name=${INPUT_RANCHER_CLUSTER}")

            namespaces_url=$(echo "${cluster}" | jq -r .data[0].links.namespaces)
            projects_url=$(echo "${cluster}" | jq -r .data[0].links.projects)

            # Get Default project id
            echo "-- Query Rancher for Default project id"
            default_project=$(curl --retry 5 -sSLf -H "${auth_header}" "${projects_url}?name=Default")
            default_project_id=$(echo "${default_project}" | jq -r .data[0].id)

            # Add namespace to Default project
            echo "-- Add ${INPUT_NAMESPACE} to Default project ${default_project_id}"
            curl --retry 5 -sSLf -H "${auth_header}" \
                -H 'Accept: application/json' \
                -H 'Content-Type: application/json' \
                -X POST "${namespaces_url}/${INPUT_NAMESPACE}?action=move" \
                -d "{\"projectId\":\"${default_project_id}\"}"
            ;;

        pod-restart)
            # Scale controller object to 0 then back to original value.
            rancher_get_kubeconfig
            is_set INPUT_NAMESPACE
            is_set INPUT_OBJECT_NAME

            replicas=$(k get -n "${INPUT_NAMESPACE}" "${INPUT_OBJECT_NAME}" -o=jsonpath='{.spec.replicas}{"\n"}')
            echo "-- ${INPUT_OBJECT_NAME} original scale: ${replicas}"

            echo "-- Scale ${INPUT_OBJECT_NAME} to 0"
            k scale -n "${INPUT_NAMESPACE}" "${INPUT_OBJECT_NAME}" --replicas=0 --timeout=5m

            # Give a pause to wait for api to stabilize.
            sleep 10

            echo "-- Scale  ${INPUT_OBJECT_NAME} to ${replicas}"
            k scale -n "${INPUT_NAMESPACE}" "${INPUT_OBJECT_NAME}" --replicas="${replicas}" --timeout=5m

            # Need to wait for pods to become healthy.
            echo "--- Sleep 60 to wait for new pods to show up."
            sleep 60

            # Get pods by match labels - yeah jsonpath AND jq!
            labels=$(k get -n "${INPUT_NAMESPACE}" "${INPUT_OBJECT_NAME}" -o=jsonpath='{.spec.selector.matchLabels}' | jq -r 'to_entries | .[] |= "\(.key)=\(.value)" | join(",")')

            k wait -n "${INPUT_NAMESPACE}" --for=condition=Ready pod -l "${labels}" --timeout=15m
            ;;

        pvcs-delete)
            # Delete PersistentVolumeClaims in target namespace.
            rancher_get_kubeconfig
            is_set INPUT_NAMESPACE

            pvcs=$(k get pvc -n "${INPUT_NAMESPACE}" -o=jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
            for p in $pvcs
            do
                echo "-- Delete PVC ${p}"
                k delete pvc "${p}" -n "${INPUT_NAMESPACE}" --now --wait --request-timeout=5m --ignore-not-found
            done
            ;;

        pvc-delete)
            # Delete a specific PVC
            rancher_get_kubeconfig
            is_set INPUT_NAMESPACE
            is_set INPUT_OBJECT_NAME

            echo "-- Delete PVC ${INPUT_OBJECT_NAME}"
            k delete pvc "${INPUT_OBJECT_NAME}" -n "${INPUT_NAMESPACE}" --now --wait --request-timeout=5m --ignore-not-found
            ;;

        secrets-create-from-file)
            # Create a secret from file or all files in a directory
            rancher_get_kubeconfig
            is_set INPUT_NAMESPACE
            is_set INPUT_SRC
            is_set INPUT_OBJECT_NAME

            k delete secret "${INPUT_OBJECT_NAME}" -n "${INPUT_NAMESPACE}" --now --wait --request-timeout=5m --ignore-not-found

            k create secret generic "${INPUT_OBJECT_NAME}" -n "${INPUT_NAMESPACE}" \
                --from-file="${INPUT_SRC}"
            ;;

        configmap-create-from-file)
            # Create a secret from file or all files in a directory
            rancher_get_kubeconfig
            is_set INPUT_NAMESPACE
            is_set INPUT_SRC
            is_set INPUT_OBJECT_NAME

            k delete configmap "${INPUT_OBJECT_NAME}" -n "${INPUT_NAMESPACE}" --now --wait --request-timeout=5m --ignore-not-found

            k create configmap "${INPUT_OBJECT_NAME}" -n "${INPUT_NAMESPACE}" \
                --from-file="${INPUT_SRC}"
            ;;

        toolbox-copy)
            # Copy files to blue/green fog-ingest toolbox container.
            rancher_get_kubeconfig
            is_set INPUT_NAMESPACE
            is_set INPUT_INGEST_COLOR
            is_set INPUT_SRC
            is_set INPUT_DST

            echo "-- Get toolbox pod"
            instance="fog-ingest-${INPUT_INGEST_COLOR}"
            toolbox=$(k get pods -n "${INPUT_NAMESPACE}" -l "app.kubernetes.io/instance=${instance},app=toolbox" -o=name | sed -r 's/pod\///')

            echo "-- Toolbox: ${toolbox}"
            echo "-- Source: ${INPUT_SRC}"
            echo "-- Destination: ${INPUT_DST}"
            echo ""
            k cp -n "${INPUT_NAMESPACE}" "${INPUT_SRC}" "${toolbox}:${INPUT_DST}" -c toolbox
            ;;

        toolbox-exec)
            # Execute commands on blue/green fog-ingest toolbox container.
            rancher_get_kubeconfig
            is_set INPUT_NAMESPACE
            is_set INPUT_COMMAND
            is_set INPUT_INGEST_COLOR

            echo "-- Get toolbox pod"
            instance="fog-ingest-${INPUT_INGEST_COLOR}"
            toolbox=$(k get pods -n "${INPUT_NAMESPACE}" -l "app.kubernetes.io/instance=${instance},app=toolbox" -o=name | sed -r 's/pod\///')

            echo "-- Toolbox: ${toolbox}"
            echo "-- execute command:"
            echo "   ${INPUT_COMMAND}"
            echo ""
            toolbox_cmd "${toolbox}" "${INPUT_COMMAND}"
            ;;
        kubectl-exec)
	    # setup kubeconfig and execute supplied command
            rancher_get_kubeconfig
            exec /bin/bash -c "$@"
	    ;;
        *)
            error_exit "Command ${INPUT_ACTION} not recognized"
            ;;
    esac
else
    # Run arbitrary commands
    exec "$@"
fi
