#!/usr/bin/env bash
set -uo pipefail
##################################################################################
# by Gosha Belenkiy
##################################################################################
log_to_file() {
    local msg="${1-}"

    printf '%s %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$msg" >> "$LOG_FILE"
}
# log <color> <message>
# Only the color is passed through %b (it holds literal \033 sequences);
# the message is printed verbatim, so backslashes in it are not interpreted.
log() {
    local color="${1-}"
    local msg="${2-}"

    printf '%s %b%s%b\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$color" "$msg" "${color:+$NC}"
}
log_title() {
    log_to_file "${1-}"
    log "$BLUE" "${1-}"
}
log_info() {
    log_to_file "${1-}"
    log "" "${1-}"
}
log_error() {
    log_to_file "${1-}"
    log "$RED" "${1-}"
}
log_success() {
    log_to_file "${1-}"
    log "$GREEN" "${1-}"
}
##################################################################################
# Send SOMA command
##################################################################################
runSoma() {
    local DP_USERNAME=$1
    local DP_PASSWORD=$2
    local DP_SOMA_URL=$3
    local DP_SOMA_REQ=$4
    local DP_SOMA_REQ_FILENAME=$5
    local EXTRA_CURL_ARGS=$6
    local VALIDATE_OUTPUT=$7

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

    # local soma_response
    local soma_response
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
    local DP_USERNAME=$1
    local DP_PASSWORD=$2
    local DP_SOMA_URL=$3
    local DP_CERTIFICATE=$4
    local DP_SB_DST_FOLDER=$5

    local SOMA_REQ
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
    printf '%s' "$soma_response"
}
##################################################################################
# SOMA - Run Quiesce Domain
##################################################################################
ampQuiesceDomain() {
    local DP_USERNAME=$1
    local DP_PASSWORD=$2
    local DP_SOMA_URL=$3
    local DP_DOMAIN_TO_QUIESCE=$4
    local QUIESCE_TIMEOUT=$5

    local AMP_REQ
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
    printf '%s' "$soma_response"
}
##################################################################################
# AMP - Run UnQuiesce Domain
##################################################################################
ampUnQuiesceDomain() {
    local DP_USERNAME=$1
    local DP_PASSWORD=$2
    local DP_SOMA_URL=$3
    local DP_DOMAIN_TO_UNQUIESCE=$4

    local AMP_REQ
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
    printf '%s' "$soma_response"
}
##################################################################################
# SOMA - GatewayPeering Switch Primary
##################################################################################
somaGatewayPeeringSwitchPrimary() {
    local DP_USERNAME=$1
    local DP_PASSWORD=$2
    local DP_SOMA_URL=$3
    local APIC_DOMAIN_NAME=$4
    local GATEWAYPEERING_NAME=$5

    local SOMA_REQ
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
    printf '%s' "$soma_response"
}
##################################################################################
# SOMA - Get DataPower firmware status
##################################################################################
somaGetFirmwareStatus() {
    local DP_USERNAME=$1
    local DP_PASSWORD=$2
    local DP_SOMA_URL=$3

    local SOMA_REQ
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
    printf '%s' "$soma_response"
}
##################################################################################
# SOMA - Get DataPower System Settings
##################################################################################
somaGetSystemSettings() {
    local DP_USERNAME=$1
    local DP_PASSWORD=$2
    local DP_SOMA_URL=$3

    local SOMA_REQ
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
    printf '%s' "$soma_response"
}
##################################################################################
# SOMA - Get Domain status
##################################################################################
somaGetDomainStatus() {
    local DP_USERNAME=$1
    local DP_PASSWORD=$2
    local DP_SOMA_URL=$3

    local SOMA_REQ
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
    printf '%s' "$soma_response"
}
##################################################################################
# SOMA - Get GatewayPeering status
##################################################################################
somaGetGatewayPeeringStatus() {
    local DP_USERNAME=$1
    local DP_PASSWORD=$2
    local DP_SOMA_URL=$3
    local DP_DOMAIN=$4

    local SOMA_REQ
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
    printf '%s' "$soma_response"
}
##################################################################################
# SOMA - Get File
##################################################################################
somaGetFile() {
    local DP_USERNAME=$1
    local DP_PASSWORD=$2
    local DP_SOMA_URL=$3
    local DP_DOMAIN=$4
    local DP_FILE=$5

    local SOMA_REQ
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
    printf '%s' "$soma_response"
}
##################################################################################
# Extract the base64 payload of the <file> element from an XML message.
# Uses perl instead of xmlstarlet, because libxml2 refuses text nodes > 10MB
# ("huge text node" / "Extra content at the end of the document").
##################################################################################
extractFileB64() {
    perl -0777 -ne 'if (m{<(?:[\w.-]+:)?file(?:\s[^>]*)?>(.*?)</(?:[\w.-]+:)?file>}s) { ($b = $1) =~ s/\s+//g; print $b }'
}
##################################################################################
