#!/bin/sh
create_cert()
{
    export STEPDIR=/usr/local/etc/step
    export STEPPATH=${STEPDIR}/ca

    CRT_FILE=""
    KEY_FILE=""
    SAN=""
    SUBJECT=""

    while getopts "c:k:s:S:" opt
    do 
        case $opt in
          c) CRT_FILE=${OPTARG};;
          k) KEY_FILE=${OPTARG};;
          S) SUBJECT=${OPTARG};;
          s) SAN="$SAN --san ${OPTARG}";;
        esac
    done

    step ca certificate \
        --ca-url https://ca.home.where-ever.za.net:8443 \
        --provisioner=vikashb@where-ever.za.net \
        --provisioner-password-file ${STEPDIR}/provisioner.txt \
        $SAN \
        $SUBJECT \
        $CRT_FILE \
        $KEY_FILE
}

mkdir -p certs
cd certs

# create a u22-vault cert
create_cert -S u22-vault.home.where-ever.za.net \
    -s u22-vault.home.where-ever.za.net \
    -s 127.0.0.1 \
    -s 192.168.0.22 \
    -c u22-vault.home.where-ever.za.net.crt \
    -k u22-vault.home.where-ever.za.net.key

# create a u22-docker cert
create_cert -S u22-docker.home.where-ever.za.net \
    -s u22-docker.home.where-ever.za.net \
    -s 127.0.0.1 \
    -s 192.168.0.21 \
    -s 192.168.49.2 \
    -c u22-docker.home.where-ever.za.net.crt \
    -k u22-docker.home.where-ever.za.net.key

# create a u22-dev cert
create_cert -S u22-dev.home.where-ever.za.net \
    -s u22-dev.home.where-ever.za.net \
    -s 127.0.0.1 \
    -s 192.168.0.23 \
    -s 192.168.49.2 \
    -c u22-dev.home.where-ever.za.net.crt \
    -k u22-dev.home.where-ever.za.net.key

# create a u22-uat cert
create_cert -S u22-uat.home.where-ever.za.net \
    -s u22-uat.home.where-ever.za.net \
    -s 127.0.0.1 \
    -s 192.168.0.23 \
    -s 192.168.49.2 \
    -c u22-uat.home.where-ever.za.net.crt \
    -k u22-uat.home.where-ever.za.net.key

# create a u22-prod cert
create_cert -S u22-prod.home.where-ever.za.net \
    -s u22-prod.home.where-ever.za.net \
    -s 127.0.0.1 \
    -s 192.168.0.24 \
    -s 192.168.49.2 \
    -c u22-prod.home.where-ever.za.net.crt \
    -k u22-prod.home.where-ever.za.net.key

# create a vault-u22-dev vault cert
create_cert -S vault-u22-dev.home.where-ever.za.net \
    -s u22-dev.home.where-ever.za.net \
    -s "*.vault-system" \
    -s "*.vault-internal" \
    -s "*.cluster.local" \
    -s 127.0.0.1 \
    -s 192.168.0.23 \
    -s 192.168.49.2 \
    -c vault-u22-dev.home.where-ever.za.net.crt \
    -k vault-u22-dev.home.where-ever.za.net.key

# create a vault-u22-uat cert
create_cert -S vault-u22-uat.home.where-ever.za.net \
    -s vault-u22-uat.home.where-ever.za.net \
    -s "*.vault-system" \
    -s "*.vault-internal" \
    -s "*.cluster.local" \
    -s 127.0.0.1 \
    -s 192.168.0.23 \
    -s 192.168.49.2 \
    -c vault-u22-uat.home.where-ever.za.net.crt \
    -k vault-u22-uat.home.where-ever.za.net.key

# create a vault-u22-prod cert
create_cert -S vault-u22-prod.home.where-ever.za.net \
    -s vault-u22-prod.home.where-ever.za.net \
    -s "*.vault-system" \
    -s "*.vault-internal" \
    -s "*.cluster.local" \
    -s 127.0.0.1 \
    -s 192.168.0.24 \
    -s 192.168.49.2 \
    -c vault-u22-prod.home.where-ever.za.net.crt \
    -k vault-u22-prod.home.where-ever.za.net.key
