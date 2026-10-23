#!/usr/bin/env bash
set -uo pipefail
##################################################################################
# This automation performs the following activities:
#  * creates a DataPower Secure Backup
#  * creates a DataPower Secure Backup
#  * downloads the Secure Backup files
#  * uploads the files to a git repo
##################################################################################
# Prerequisites:
#   curl (v7.79.1)
#   xmlstarlet
#   jq
##################################################################################
# by Gosha Belenkiy
##################################################################################
if [ -z "$1" ]; then
    echo "Syntax error, aborting."
    echo "  Provide configuration filename as a parameter"
    exit
fi

if [ ! -f ./$1 ]; then
    echo "Configuration file $1 not found, aborting."
    exit
fi

. ./system.conf
mkdir -p $FOLDER_BACKUPS
mkdir -p $FOLDER_LOGS
. ./utils.sh
log "Loading configuration from ${1}"
. ${1}

if [ "$EMPTY_LOG_FILE_ON_START" = "true" ]; then
    printf "" > $LOG_FILE
fi

len=$(jq 'length' <<<"$DP_SERVERS")
if ! [[ "$len" =~ ^[0-9]+$ ]] || [ "$len" -eq 0 ]; then
    log_error "DP_SERVERS is not a valid, non-empty JSON array"
    exit
fi

log_title "====================================================================================="
log_title "Secure Backup the DataPower Gateway"
log_info "Start: $(date)"
log_info "DataPower Secure Backup folder: $DP_SB_FOLDER"
log_info "Number of DataPower gateways: ${len}"

##################################################################################
for ((i=0; i<$len; i++)); do
    # declare -i cur_ind=$(( (i+1) % len))
    declare -i cur_ind=$i
    declare CUR_DP_SERVER=$(jq -r ".[$cur_ind]" <<<"$DP_SERVERS")
    if [ -z "$CUR_DP_SERVER" ] || [ "$CUR_DP_SERVER" = "null" ]; then
        log_error "DP_SERVERS[$cur_ind] is missing or invalid"
        exit
    fi
    declare CUR_DP_MGMT_IP=$(jq -r .mgmt_ip <<<"${CUR_DP_SERVER}")
    if [ -z "$CUR_DP_MGMT_IP" ] || [ "$CUR_DP_MGMT_IP" = "null" ]; then
        log_error "DP_SERVERS[$cur_ind].mgmt_ip is missing"
        exit
    fi
    declare CUR_DP_MGMT_SOMA_PORT=$(jq -r .soma_port <<<"${CUR_DP_SERVER}")
    declare CUR_DP_USERNAME=$(jq -r .user_name <<<"${CUR_DP_SERVER}")
    declare CUR_DP_PASSWORD=$(jq -r .user_password <<<"${CUR_DP_SERVER}")
    declare CUR_SB_CERT=$(jq -r .sb_certificate <<<"${CUR_DP_SERVER}")
    declare CUR_DP_MGMT_SOMA_URL="https://${CUR_DP_MGMT_IP}:${CUR_DP_MGMT_SOMA_PORT}${DP_SOMA_URI}"
    declare CUR_DP_MGMT_AMP_URL="https://${CUR_DP_MGMT_IP}:${CUR_DP_MGMT_SOMA_PORT}${DP_AMP_URI}"

    log_title "====================================================================================="
    log_title "Start working on DP: $CUR_DP_MGMT_IP"

    ##################################################################################
    # Get the DataPower firmware details
    ##################################################################################
    log_title "${CUR_DP_MGMT_IP} ====================================================================================="
    log_title "${CUR_DP_MGMT_IP} Checking firmware status"
    declare soma_resp_firmware_status="$(somaGetFirmwareStatus $CUR_DP_USERNAME $CUR_DP_PASSWORD $CUR_DP_MGMT_SOMA_URL)"
    soma_response_analysis=$(printf '%s' "$soma_resp_firmware_status" | grep -o '</FirmwareStatus>')
    if [ "${#soma_response_analysis}" = 0 ]; then
        log_error "${CUR_DP_MGMT_IP} Failure"
        log_error "${CUR_DP_MGMT_IP} $soma_resp_firmware_status"
        exit
    fi
    firmware_version=$(printf '%s' "$soma_resp_firmware_status" | xmlstarlet sel -t -v "//Version")
    log_info "${CUR_DP_MGMT_IP} Firmware version: $firmware_version"

    ##################################################################################
    # Get the DataPower System Settings
    ##################################################################################
    log_title "====================================================================================="
    log_title "${CUR_DP_MGMT_IP} Checking System Settings"
    declare soma_resp_system_settings="$(somaGetSystemSettings $CUR_DP_USERNAME $CUR_DP_PASSWORD $CUR_DP_MGMT_SOMA_URL)"
    soma_response_analysis=$(printf '%s' "$soma_resp_system_settings" | grep -o '</SystemSettings>')
    if [ "${#soma_response_analysis}" = 0 ]; then
        log_error "${CUR_DP_MGMT_IP} Failure"
        log_error "${CUR_DP_MGMT_IP} $soma_resp_firmware_status"
        exit
    fi
    system_name=$(printf '%s' "$soma_resp_system_settings" | xmlstarlet sel -t -v "//SystemName")
    log_info "${CUR_DP_MGMT_IP} System Name: $system_name"

    if [ "$DO_QUIESCE" = "true" ]; then
        ##################################################################################
        # Gateway Peering Switch Primary 
        ##################################################################################
        log_title "${CUR_DP_MGMT_IP} ====================================================================================="
        log_title "${CUR_DP_MGMT_IP} Gateway Peering Switch Primary"
        declare -i dst_ind=$(( (i+1) % len))
        declare DST_DP_SERVER=$(jq -r ".[$dst_ind]" <<<"$DP_SERVERS")
        if [ -z "$DST_DP_SERVER" ] || [ "$DST_DP_SERVER" = "null" ]; then
            log_error "DP_SERVERS[$dst_ind] is missing or invalid"
            exit
        fi
        declare DST_DP_MGMT_IP=$(jq -r .mgmt_ip <<<"${DST_DP_SERVER}")
        if [ -z "$DST_DP_MGMT_IP" ] || [ "$DST_DP_MGMT_IP" = "null" ]; then
            log_error "DP_SERVERS[$dst_ind].mgmt_ip is missing"
            exit
        fi
        declare DST_DP_MGMT_SOMA_PORT=$(jq -r .soma_port <<<"${DST_DP_SERVER}")
        declare DST_DP_USERNAME=$(jq -r .user_name <<<"${DST_DP_SERVER}")
        declare DST_DP_PASSWORD=$(jq -r .user_password <<<"${DST_DP_SERVER}")
        declare DST_DP_MGMT_SOMA_URL="https://${DST_DP_MGMT_IP}:${DST_DP_MGMT_SOMA_PORT}${DP_SOMA_URI}"
        for cur_gateway_peering in "${GATEWAY_PEERING_SWITCHING[@]}"; do
            log_title "${CUR_DP_MGMT_IP} ====================================================================================="
            log_title "${CUR_DP_MGMT_IP} Gateway Peering Switch Primary: domain=$QUIESCE_DOMAIN peering=$cur_gateway_peering"
            declare soma_resp_gateway_peering_switch_primary="$(somaGatewayPeeringSwitchPrimary $DST_DP_USERNAME $DST_DP_PASSWORD $DST_DP_MGMT_SOMA_URL $QUIESCE_DOMAIN $cur_gateway_peering)"
            log_info "${CUR_DP_MGMT_IP} $soma_resp_gateway_peering_switch_primary"
        done

        ##################################################################################
        # Quiesce domain
        ##################################################################################
        log_title "${CUR_DP_MGMT_IP} ====================================================================================="
        log_title "${CUR_DP_MGMT_IP} Quiescing domain: ${QUIESCE_DOMAIN}"
        declare soma_resp_quisce_domain="$(ampQuiesceDomain $CUR_DP_USERNAME $CUR_DP_PASSWORD $CUR_DP_MGMT_AMP_URL $QUIESCE_DOMAIN $QUIESCE_TIMEOUT)"
        soma_response_analysis=$(printf '%s' "$soma_resp_quisce_domain" | grep -o '<result>ok</result>')
        if [ "${#soma_response_analysis}" = 0 ]; then
            log_error "${CUR_DP_MGMT_IP} Failure"
            log_error "${CUR_DP_MGMT_IP} $soma_resp_quisce_domain"
            exit
        fi
        log_info "${CUR_DP_MGMT_IP} Success"

        log_title "${CUR_DP_MGMT_IP} ====================================================================================="
        log_title "${CUR_DP_MGMT_IP} Waiting to let the domain quiesce finish"
        declare -i quiesce_check_count=0
        while
            ##################################################################################
            # Wait to let the quiesce finish
            ##################################################################################
            log_info "${CUR_DP_MGMT_IP} Waiting for ${QUIESCE_STATUS_POLL_INTERVAL} seconds"
            sleep $QUIESCE_STATUS_POLL_INTERVAL

            ##################################################################################
            # Verify that domain quiesced
            ##################################################################################
            log_info "${CUR_DP_MGMT_IP} Verifing that domain quiesced"
            declare soma_response="$(somaGetDomainStatus $CUR_DP_USERNAME $CUR_DP_PASSWORD $CUR_DP_MGMT_SOMA_URL)"
            domain_status=$(printf '%s' "$soma_response" | xml sel -t -v "normalize-space(//DomainStatus[Domain='$QUIESCE_DOMAIN']/QuiesceState)" -)
            log_info "${CUR_DP_MGMT_IP} Domain status: $domain_status"
            quiesce_check_count+=1
            if [ "$domain_status" != "quiesced" ] && [ "$quiesce_check_count" -ge "$QUIESCE_STATUS_POLL_MAX_CHECKS" ]; then
                log_error "${CUR_DP_MGMT_IP} Domain did not quiesce after ${quiesce_check_count} checks, aborting"
                exit
            fi

            [ "$domain_status" != "quiesced" ]
        do true;done
    fi

    ##################################################################################
    # Secure Backup
    ##################################################################################
    log_title "${CUR_DP_MGMT_IP} ====================================================================================="
    log_title "${CUR_DP_MGMT_IP} Creating a Secure Backup"
    declare soma_response="$(somaSecureBackup $CUR_DP_USERNAME $CUR_DP_PASSWORD $CUR_DP_MGMT_SOMA_URL $CUR_SB_CERT $DP_SB_FOLDER)"

    soma_response_analysis=$(printf '%s' "$soma_response" | grep -o 'OK')
    if [ ! "$soma_response_analysis" = "OK" ]; then
        log_error "${CUR_DP_MGMT_IP} Failure"
        log_error "${CUR_DP_MGMT_IP} $soma_response"
        exit
    fi
    log_info "${CUR_DP_MGMT_IP} Success"

    if [ "$DO_QUIESCE" = "true" ]; then
        ##################################################################################
        # Un-Quiesce domain
        ##################################################################################
        log_title "${CUR_DP_MGMT_IP} ====================================================================================="
        log_title "${CUR_DP_MGMT_IP} Unquiescing domain ${QUIESCE_DOMAIN}"
        declare soma_resp_unquisce_domain="$(ampUnQuiesceDomain $CUR_DP_USERNAME $CUR_DP_PASSWORD $CUR_DP_MGMT_AMP_URL $QUIESCE_DOMAIN)"
        soma_response_analysis=$(printf '%s' "$soma_resp_unquisce_domain" | grep -o '<result>ok</result>')
        if [ "${#soma_response_analysis}" = 0 ]; then
            log_error "${CUR_DP_MGMT_IP} Failure"
            log_error "${CUR_DP_MGMT_IP} $soma_resp_unquisce_domain"
            exit
        fi
        log_info "${CUR_DP_MGMT_IP} Success"
    fi

    ##################################################################################
    # Calculating local path to store the Secure Backup files
    ##################################################################################
    log_title "${CUR_DP_MGMT_IP} ====================================================================================="
    log_title "${CUR_DP_MGMT_IP} Downloading Secure Backup files"
    # LOCAL_SB_FOLDER=$FOLDER_BACKUPS/$CUR_DP_MGMT_IP/$firmware_version/$SB_FOLDER
    LOCAL_SB_FOLDER=$FOLDER_BACKUPS/$system_name/$firmware_version/$SB_FOLDER
    log_info "${CUR_DP_MGMT_IP} Local Secure Backup folder: $LOCAL_SB_FOLDER"
    mkdir -p "$LOCAL_SB_FOLDER"

    ##################################################################################
    # Download Secure Backup files
    ##################################################################################
    log_info "${CUR_DP_MGMT_IP} Downloading $DP_SB_FOLDER/backupmanifest.xml"
    DP_FILE_TO_GET="$DP_SB_FOLDER/backupmanifest.xml"
    declare -a soma_response_get_file="$(somaGetFile $CUR_DP_USERNAME $CUR_DP_PASSWORD $CUR_DP_MGMT_SOMA_URL "default" "$DP_FILE_TO_GET")"
    analysis=$(echo "$soma_response_get_file" | grep -o "$DP_FILE_TO_GET")
    if [ ! "$analysis" = "$DP_FILE_TO_GET" ]; then
        log_error "${CUR_DP_MGMT_IP} File download failed"
        log_error "${CUR_DP_MGMT_IP} $soma_response_get_file"
        exit
    fi

    ##################################################################################
    # Extract the file base64 value from the SOAP response
    ##################################################################################
    backupmanifest_b64=$(printf '%s' "$soma_response_get_file" | xml sel -t -v "/*[local-name()='Envelope']/*[local-name()='Body']/*[local-name()='response']/*[local-name()='file']" -)
    printf '%s' "$backupmanifest_b64" | base64 -d > "$LOCAL_SB_FOLDER/backupmanifest.xml"
    # log_info "${CUR_DP_MGMT_IP} File downloaded successfully"

    ##################################################################################
    # Download all Secure Backup files per the manifest
    ##################################################################################
    xmlstarlet sel -t -v '//backupmanifest/files/file/filename' --nl "$LOCAL_SB_FOLDER/backupmanifest.xml" |
    while IFS= read -r cur_file; do
        DP_FILE_TO_GET="$DP_SB_FOLDER/$cur_file"
        log_info "${CUR_DP_MGMT_IP} Downloading $DP_FILE_TO_GET"
        declare -a soma_response_get_file="$(somaGetFile $CUR_DP_USERNAME $CUR_DP_PASSWORD $CUR_DP_MGMT_SOMA_URL "default" "$DP_FILE_TO_GET")"
        analysis=$(echo "$soma_response_get_file" | grep -o "$DP_FILE_TO_GET")
        if [ ! "$analysis" = "$DP_FILE_TO_GET" ]; then
            log_error "${CUR_DP_MGMT_IP} File download failed"
            log_error "${CUR_DP_MGMT_IP} $soma_response_get_file"
            # exit
        fi
        file_b64=$(printf '%s' "$soma_response_get_file" | xml sel -t -v "/*[local-name()='Envelope']/*[local-name()='Body']/*[local-name()='response']/*[local-name()='file']" -)
        printf '%s' "$file_b64" | base64 -d > "$LOCAL_SB_FOLDER/$cur_file"
        # log_info "${CUR_DP_MGMT_IP} File downloaded successfully"
    done

    log_title "${CUR_DP_MGMT_IP} ====================================================================================="
    log_title "${CUR_DP_MGMT_IP} Downloaded Secure Backup files:"
    log_info "$(ls -lh "$LOCAL_SB_FOLDER")"
done

if [ "$ADD_TO_GIT" = "true" ]; then
    log_title "====================================================================================="
    log_title "Pushing Secure Backup files to git repository"
    log_info "Git remote=$GIT_REMOTE_NAME git branch=$GIT_BRANCH_NAME"
    git pull $GIT_REMOTE_NAME $GIT_BRANCH_NAME
    git add $LOCAL_SB_FOLDER\*
    git commit -m "Automated push"
    git push $GIT_REMOTE_NAME $GIT_BRANCH_NAME
fi

log_title "====================================================================================="
log_title "Script ended: $(date)"
log_title "====================================================================================="