#!/usr/bin/env bash
set -uo pipefail
##################################################################################
# by Gosha Belenkiy
##################################################################################
log_to_file() {
    MSG=$1

    TIME=$(date +'%Y-%m-%d %H:%M:%S')
    echo "$TIME $MSG" >> $LOG_FILE
}
log(){
    MSG="$1"

    TIME=$(date +'%Y-%m-%d %H:%M:%S')
    # echo "$TIME $MSG"
    echo -e "$TIME $MSG"
}
log_title() {
    MSG=$1

    log_to_file "$MSG"
    log $BLUE"$MSG"$NC
}
log_info() {
    MSG=$1

    log_to_file "$MSG"
    log "$MSG"
    # log $PURPLE"$MSG"$NC
}
log_error() {
    MSG=$1

    log_to_file "$MSG"
    log $RED"$MSG"$NC
}
log_success() {
    MSG=$1

    log_to_file "$MSG"
    log $GREEN"$MSG"$NC
}
##################################################################################
# Send SOMA command
##################################################################################
runSoma() {
    DP_USERNAME=$1
    DP_PASSWORD=$2
    DP_SOMA_URL=$3
    DP_SOMA_REQ=$4
    DP_SOMA_REQ_FILENAME=$5
    EXTRA_CURL_ARGS=$6
    VALIDATE_OUTPUT=$7

    declare -a soma_cli=(curl -s -k --connect-timeout $CURL_CONNECTION_TIMEOUT)

    # Set POST HTTP method
    if [ ! -z "$DP_SOMA_REQ" ]; then
        soma_cli+=(-X POST)
    fi

    # Add credentials
    if [ ! -z "$DP_USERNAME" ]; then
        soma_cli+=(-u "$DP_USERNAME:$DP_PASSWORD")
        # basic_auth_header=$(printf '%s' "${DP_USERNAME}:${DP_PASSWORD}" | base64)
        # soma_cli+=("-H \"Authorization: Basic ${basic_auth_header}\"")
    fi

    # Add HTTP URL parameter
    soma_cli+=("$DP_SOMA_URL")

    # Add request parameter
    if [ ! -z "$DP_SOMA_REQ" ]; then
        soma_cli+=(-d "$DP_SOMA_REQ")
        # soma_cli+=(-d \'"$DP_SOMA_REQ"\')
    fi

    if [ ! -z "$EXTRA_CURL_ARGS" ]; then
        soma_cli+=($EXTRA_CURL_ARGS)
    fi

    if [ ! -z "$DP_SOMA_REQ_FILENAME" ]; then
        soma_cli+=(-T "$DP_SOMA_REQ_FILENAME")
    fi

    if [ "${DEBUG:-false}" = "true" ]; then
        log_to_file "runSoma() SOMA curl cli=${soma_cli[*]}"
    fi

    soma_response=$("${soma_cli[@]}")

    if [ "${DEBUG:-false}" = "true" ]; then
        log_to_file "runSoma() SOMA response=${soma_response}"
    fi
    printf '%s' "$soma_response"
}
##################################################################################
# SOMA - Run Secure Backup
##################################################################################
somaSecureBackup() {
    DP_USERNAME=$1
    DP_PASSWORD=$2
    DP_SOMA_URL=$3
    DP_CERTIFICATE=$4
    DP_SB_DST_FOLDER=$5

    SOMA_REQ=$(cat <<-EOF
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:dp="http://www.datapower.com/schemas/management">
    <soapenv:Body>
		<dp:request domain="default">
			<dp:do-action>
				<SecureBackup>
					<cert>$DP_CERTIFICATE</cert>
					<destination>$DP_SB_DST_FOLDER</destination>
					<include-iscsi>$INCLUDE_ISCSI</include-iscsi>
					<include-raid>$INCLUDE_RAID</include-raid>
				</SecureBackup>
			</dp:do-action>
		</dp:request>
    </soapenv:Body>
</soapenv:Envelope>
EOF
)

    declare -a soma_response="$(runSoma $DP_USERNAME $DP_PASSWORD $DP_SOMA_URL "${SOMA_REQ}" '' '' '' 'false')"
    echo $soma_response
}
##################################################################################
# SOMA - Run Quiesce Domain
##################################################################################
ampQuiesceDomain() {
    DP_USERNAME=$1
    DP_PASSWORD=$2
    DP_SOMA_URL=$3
    DP_DOMAIN_TO_QUIESCE=$4
    QUIESCE_TIMEOUT=$5

    AMP_REQ=$(cat <<-EOF
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:dp="http://www.datapower.com/schemas/appliance/management/3.0">
    <soapenv:Body>
        <dp:QuiesceRequest>
            <dp:Domain>
                <dp:Name>$DP_DOMAIN_TO_QUIESCE</dp:Name>
                <dp:Timeout>$QUIESCE_TIMEOUT</dp:Timeout>
            </dp:Domain>
        </dp:QuiesceRequest>
    </soapenv:Body>
</soapenv:Envelope>
EOF
)

    declare -a soma_response="$(runSoma $DP_USERNAME $DP_PASSWORD $DP_SOMA_URL "${AMP_REQ}" '' '' '' 'false')"
    echo $soma_response
}
##################################################################################
# AMP - Run UnQuiesce Domain
##################################################################################
ampUnQuiesceDomain() {
    DP_USERNAME=$1
    DP_PASSWORD=$2
    DP_SOMA_URL=$3
    DP_DOMAIN_TO_UNQUIESCE=$4

    AMP_REQ=$(cat <<-EOF
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:dp="http://www.datapower.com/schemas/appliance/management/3.0">
    <soapenv:Body>
        <dp:UnquiesceRequest>
            <dp:Domain>
                <dp:Name>$DP_DOMAIN_TO_UNQUIESCE</dp:Name>
            </dp:Domain>
        </dp:UnquiesceRequest>
    </soapenv:Body>
</soapenv:Envelope>
EOF
)

    declare -a soma_response="$(runSoma $DP_USERNAME $DP_PASSWORD $DP_SOMA_URL "${AMP_REQ}" '' '' '' 'false')"
    echo $soma_response
}
##################################################################################
# SOMA - GatewayPeering Switch Primary
##################################################################################
somaGatewayPeeringSwitchPrimary() {
    DP_USERNAME=$1
    DP_PASSWORD=$2
    DP_SOMA_URL=$3
    APIC_DOMAIN_NAME=$4
    GATEWAYPEERING_NAME=$5

    SOMA_REQ=$(cat <<-EOF
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:dp="http://www.datapower.com/schemas/management">
    <soapenv:Body>
        <dp:request domain="$APIC_DOMAIN_NAME">
            <dp:do-action>
                <GatewayPeeringSwitchPrimary>
                    <ObjectName>$GATEWAYPEERING_NAME</ObjectName>
                </GatewayPeeringSwitchPrimary>
            </dp:do-action>
        </dp:request>
    </soapenv:Body>
</soapenv:Envelope>
EOF
)

    declare -a soma_response="$(runSoma $DP_USERNAME $DP_PASSWORD $DP_SOMA_URL "${SOMA_REQ}" '' '' '' 'false')"
    echo $soma_response
}
##################################################################################
# SOMA - Get DataPower firmware status
##################################################################################
somaGetFirmwareStatus() {
    DP_USERNAME=$1
    DP_PASSWORD=$2
    DP_SOMA_URL=$3

    SOMA_REQ=$(cat <<-EOF
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:dp="http://www.datapower.com/schemas/management">
    <soapenv:Body>
        <dp:request>
            <dp:get-status class="FirmwareStatus"/>
        </dp:request>
    </soapenv:Body>
</soapenv:Envelope>
EOF
)

    declare -a soma_response="$(runSoma $DP_USERNAME $DP_PASSWORD $DP_SOMA_URL "${SOMA_REQ}" '' '' '' 'false')"
    echo $soma_response
}
##################################################################################
# SOMA - Get DataPower System Settings
##################################################################################
somaGetSystemSettings() {
    DP_USERNAME=$1
    DP_PASSWORD=$2
    DP_SOMA_URL=$3

    SOMA_REQ=$(cat <<-EOF
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:dp="http://www.datapower.com/schemas/management">
    <soapenv:Body>
        <dp:request>
            <dp:get-config class="SystemSettings"/>
        </dp:request>
    </soapenv:Body>
</soapenv:Envelope>
EOF
)

    declare -a soma_response="$(runSoma $DP_USERNAME $DP_PASSWORD $DP_SOMA_URL "${SOMA_REQ}" '' '' '' 'false')"
    echo $soma_response
}
##################################################################################
# SOMA - Get Domain status
##################################################################################
somaGetDomainStatus() {
    DP_USERNAME=$1
    DP_PASSWORD=$2
    DP_SOMA_URL=$3

    SOMA_REQ=$(cat <<-EOF
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:dp="http://www.datapower.com/schemas/management">
    <soapenv:Body>
        <dp:request>
            <dp:get-status class="DomainStatus"/>
        </dp:request>
    </soapenv:Body>
</soapenv:Envelope>
EOF
)

    declare -a soma_response="$(runSoma $DP_USERNAME $DP_PASSWORD $DP_SOMA_URL "${SOMA_REQ}" '' '' '' 'false')"
    echo $soma_response
}
##################################################################################
# SOMA - Get GatewayPeering status
##################################################################################
somaGetGatewayPeeringStatus() {
    DP_USERNAME=$1
    DP_PASSWORD=$2
    DP_SOMA_URL=$3
    DP_DOMAIN=$4

    SOMA_REQ=$(cat <<-EOF
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:dp="http://www.datapower.com/schemas/management">
    <soapenv:Body>
        <dp:request domain="$DP_DOMAIN">
            <dp:get-status class="ObjectStatus" object-class="GatewayPeering"/>
        </dp:request>
    </soapenv:Body>
</soapenv:Envelope>
EOF
)

    declare -a soma_response="$(runSoma $DP_USERNAME $DP_PASSWORD $DP_SOMA_URL "${SOMA_REQ}" '' '' '' 'false')"
    echo $soma_response
}
##################################################################################
# SOMA - Get File
##################################################################################
somaGetFile() {
    DP_USERNAME=$1
    DP_PASSWORD=$2
    DP_SOMA_URL=$3
    DP_DOMAIN=$4
    DP_FILE=$5

    SOMA_REQ=$(cat <<-EOF
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:dp="http://www.datapower.com/schemas/management">
    <soapenv:Body>
        <dp:request domain="$DP_DOMAIN">
            <dp:get-file name="$DP_FILE"/>
        </dp:request>
    </soapenv:Body>
</soapenv:Envelope>
EOF
)

    declare -a soma_response="$(runSoma $DP_USERNAME $DP_PASSWORD $DP_SOMA_URL "${SOMA_REQ}" '' '' '' 'false')"
    echo $soma_response
}
