#!/bin/sh

export STEPCAURL="https://ica.home.where-ever.za.net:443"
export STEPDIR=/usr/local/etc/step-ca
export STEPPATH=${STEPDIR}/ca
export CERTDIR=$STEPDIR/certs
export TMPDIR=$STEPDIR/tmp

usage() {
   cat <<EOT
Usage:
    -c cert
    -s SAN ( can be specified multiple times. eg -s 192.168.0.1 -s gw.local )
    -h Help
EOT
   exit 2
}

CERT_SUBJECT=""
SAN=""

while getopts "c:s:" opt
do
    case $opt in
      c) CERT_SUBJECT=${OPTARG};;
      s) SAN="$SAN --san ${OPTARG}";;
      h) usage;;
      *) usage;;
    esac
done

[ -z $CERT_SUBJECT ] && usage
[ "X${SAN} --san " = "X --san " ] && usage

CRT_FILE="${CERT_SUBJECT}.crt"
KEY_FILE="${CERT_SUBJECT}.key"

step ca certificate \
    --ca-url ${STEPCAURL} \
    --provisioner=vikashb@where-ever.za.net \
    --provisioner-password-file ${STEPDIR}/provisioner.password.txt \
    $SAN \
    $CERT_SUBJECT \
    $CRT_FILE \
    $KEY_FILE

chown -R vikashb ~vikashb/certs/
exit

# Examples
# create a u22-vault cert
sudo ./create-cert.sh -c u22-vault.home.where-ever.za.net \
    -s u22-vault.home.where-ever.za.net \
    -s 127.0.0.1 \
    -s 192.168.0.22 

# create a u22-dev cert
sudo ./create-cert.sh -c u22-dev.home.where-ever.za.net \
    -s u22-dev.home.where-ever.za.net \
    -s 127.0.0.1 \
    -s 192.168.0.23 \
    -s 192.168.49.2 

# create a u22-uat cert
sudo ./create-cert.sh -c u22-uat.home.where-ever.za.net \
    -s u22-uat.home.where-ever.za.net \
    -s 127.0.0.1 \
    -s 192.168.0.23 \
    -s 192.168.49.2 

# create a u22-prod cert
sudo ./create-cert.sh -c u22-prod.home.where-ever.za.net \
    -s u22-prod.home.where-ever.za.net \
    -s 127.0.0.1 \
    -s 192.168.0.24 \
    -s 192.168.49.2 

# create a vault-u22-dev vault cert
sudo ./create-cert.sh -c vault-u22-dev.home.where-ever.za.net \
    -s vault-active.vault-system.svc.cluster.local \
    -s u22-dev.home.where-ever.za.net \
    -s "*.vault-system" \
    -s "*.vault-internal" \
    -s "*.cluster.local" \
    -s "*.svc.cluster.local" \
    -s "*.vault-system.svc.cluster.local" \
    -s 127.0.0.1 \
    -s 192.168.0.23 \
    -s 192.168.49.2

# create a vault-u22-uat cert
sudo ./create-cert.sh -c vault-u22-uat.home.where-ever.za.net \
    -s vault-u22-uat.home.where-ever.za.net \
    -s "*.vault-system" \
    -s "*.vault-internal" \
    -s "*.cluster.local" \
    -s 127.0.0.1 \
    -s 192.168.0.23 \
    -s 192.168.49.2 

# create a vault-u22-prod cert
sudo ./create-cert.sh -c vault-u22-prod.home.where-ever.za.net \
    -s vault-u22-prod.home.where-ever.za.net \
    -s "*.vault-system" \
    -s "*.vault-internal" \
    -s "*.cluster.local" \
    -s 127.0.0.1 \
    -s 192.168.0.24 \
    -s 192.168.49.2 
