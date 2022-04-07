#!/bin/bash

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
            --version "${INPUT_CHART_VERSION}" ${sets}
        then
            echo_exit "Deploy Successful"
        else
            sleep 10
        fi
    done
    error_exit "Helm Deployment Failed"
}


if [ -n "${INPUT_ACTION}" ]
then
    case "${INPUT_ACTION}" in
        s3-publish)
            is_set INPUT_CHART_APP_VERSION
            is_set INPUT_CHART_PATH
            is_set INPUT_CHART_VERSION
            is_set INPUT_AWS_ACCESS_KEY_ID
            is_set INPUT_AWS_DEFAULT_REGION
            is_set INPUT_AWS_SECRET_ACCESS_KEY
            is_set INPUT_CHART_REPO

            # Convert input to AWS env vars.
            export AWS_ACCESS_KEY_ID="${INPUT_AWS_ACCESS_KEY_ID}"
            export AWS_DEFAULT_REGION="${INPUT_AWS_DEFAULT_REGION}"
            export AWS_SECRET_ACCESS_KEY="${INPUT_AWS_SECRET_ACCESS_KEY}"

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
            helm repo add repo "${INPUT_CHART_REPO}"

            echo "-- Push chart"
            chart_name=$(basename "${INPUT_CHART_PATH}")
            helm s3 push --relative --force ".tmp/charts/${chart_name}-${INPUT_CHART_VERSION}.tgz" repo
            ;;

        namespace-delete)
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
            k create ns "${INPUT_NAMESPACE}" || echo "Namespace already exists"

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

        delete-release)
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

        delete-pvcs)
            rancher_get_kubeconfig
            is_set INPUT_NAMESPACE

            pvcs=$(k get pvc -n "${INPUT_NAMESPACE}" -o=jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
            for p in $pvcs
            do
                echo "-- Delete PVC ${p}"
                k delete pvc "${p}" -n "${INPUT_NAMESPACE}" --now --wait --request-timeout=5m --ignore-not-found
            done
            ;;

        helm-deploy)
            rancher_get_kubeconfig
            is_set INPUT_NAMESPACE
            is_set INPUT_RELEASE_NAME
            is_set INPUT_CHART_VERSION
            is_set INPUT_CHART_NAME
            is_set INPUT_CHART_WAIT_TIMEOUT

            echo "-- Add chart repo ${INPUT_CHART_REPO}"
            repo_name=$(dd bs=10 count=1 if=/dev/urandom 2>/dev/null | base64 | tr -d +/=)
            echo "-- Repo random name ${repo_name}"
            helm repo add "${repo_name}" "${INPUT_CHART_REPO}"
            helm repo update

            sets=$(echo -n "${INPUT_CHART_SET}" | tr '\n' ' ')

            if [ -n "${INPUT_CHART_VALUES}" ]
            then
                helm_upgrade_with_values "${repo_name}" "${sets}"
            else
                helm_upgrade "${repo_name}" "${sets}"
            fi
            ;;

        fog-ingest-activate)
            rancher_get_kubeconfig
            is_set INPUT_NAMESPACE
            is_set INPUT_INGEST_COLOR
            
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
                    command="fog_ingest_client --uri 'insecure-fog-ingest://${p}:3226' get-status 2>/dev/null | jq -r .mode"
                    mode=$(k exec -n "${INPUT_NAMESPACE}" "${toolbox}" -- /bin/bash -c "${command}")

                    if [ "${mode}" == "Active" ]
                    then
                        echo "-- ${p} Active ingest found, retiring."
                        command="fog_ingest_client --uri 'insecure-fog-ingest://${p}:3226' retire 2>/dev/null | jq -r ."
                        k exec -n "${INPUT_NAMESPACE}" "${toolbox}" -- /bin/bash -c "${command}"
                        active_found="yes"
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
                command="fog_ingest_client --uri 'insecure-fog-ingest://${p}:3226' get-status 2>/dev/null | jq -r .mode"
                mode=$(k exec -n "${INPUT_NAMESPACE}" "${toolbox}" -- /bin/bash -c "${command}")

                if [ "${mode}" == "Active" ]
                then
                    echo_exit "-- Active ingest found, no action needed."
                fi
            done

            echo "-- No Active Primary ingest found. Activating ingest 0."
            command="fog_ingest_client --uri 'insecure-fog-ingest://${instance}-0.${instance}:3226' activate"
            k exec -n "${INPUT_NAMESPACE}" "${toolbox}" -- /bin/bash -c "${command}"
            ;;

        sample-keys-create-secrets)
            rancher_get_kubeconfig
            is_set INPUT_NAMESPACE
            is_set INPUT_INITIAL_KEYS_SEED
            is_set INPUT_FOG_KEYS_SEED
            is_set INPUT_FOG_REPORT_SIGNING_CA_CERT

            k delete secret sample-keys-seeds -n "${INPUT_NAMESPACE}" --now --wait --request-timeout=5m --ignore-not-found

            k create secret generic sample-keys-seeds -n "${INPUT_NAMESPACE}" \
                --from-literal=FOG_KEYS_SEED="${INPUT_FOG_KEYS_SEED}" \
                --from-literal=INITIAL_KEYS_SEED="${INPUT_INITIAL_KEYS_SEED}" \
                --from-literal=FOG_REPORT_SIGNING_CA_CERT="${INPUT_FOG_REPORT_SIGNING_CA_CERT}"
            ;;

        pod-restart)
            # Scale controller object to 0 then back to original value.
            rancher_get_kubeconfig
            is_set INPUT_NAMESPACE
            is_set INPUT_OBJECT_NAME
            
            replicas=$(k get -n "${INPUT_NAMESPACE}" "${INPUT_OBJECT_NAME}" -o=jsonpath='{.spec.replicas}{"\n"}')
            echo "${INPUT_OBJECT_NAME} original scale: ${replicas}"

            echo "Scale ${INPUT_OBJECT_NAME} to 0"
            k scale -n "${INPUT_NAMESPACE}" "${INPUT_OBJECT_NAME}" --replicas=0 --timeout=5m

            echo "Scale  ${INPUT_OBJECT_NAME} to ${replicas}"
            k scale -n "${INPUT_NAMESPACE}" "${INPUT_OBJECT_NAME}" --replicas="${replicas}" --timeout=5m
            ;;

        toolbox-exec)
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
            k exec -n "${INPUT_NAMESPACE}" "${toolbox}" -- /bin/bash -c "${INPUT_COMMAND}"
            ;;

        toolbox-copy)
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
        *)
            error_exit "Command ${INPUT_ACTION} not recognized"
            ;;
    esac
else
    # Run arbitrary commands
    exec "$@"
fi
