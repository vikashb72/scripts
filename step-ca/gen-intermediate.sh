#!/bin/sh

export STEPCAURL="https://ica.home.where-ever.za.net:443"
export STEPDIR=/usr/local/etc/step-ca
export STEPPATH=${STEPDIR}/ca
export CERTDIR=$STEPDIR/certs
export TMPDIR=$STEPDIR/tmp

usage() {
   cat <<EOT
Usage:
    -c CA name
    -f filename
    -p password (default "")
    -h Help
EOT
   exit 2
}

CANAME=""
OUTFILE=""
PASSWORD=""
PASSWORD_FILE=""

while getopts "c:f:p:" opt
do
    case $opt in
      c) CANAME=${OPTARG};;
      f) OUTFILE=${OPTARG};;
      p) PASSWORD=${OPTARG};;
      h) usage;;
      *) usage;;
    esac
done

[ -z "${CANAME}" ] && usage
[ -z "${OUTFILE}" ] && usage

mkdir -p ${TMPDIR}/ica/

PASSWORD_FILE=${TMPDIR}/ica/${OUTFILE}.password

touch ${PASSWORD_FILE}

[ ! -z $PASSWORD ] && echo "$PASSWORD" > ${PASSWORD_FILE}

# create Intermediate CA
step certificate create "${CANAME}" \
   --csr \
   --password-file ${PASSWORD_FILE} \
   ${TMPDIR}/ica/${OUTFILE}.csr \
   ${TMPDIR}/ica/${OUTFILE}.key

# sign new Intermediate
step certificate sign \
    --profile intermediate-ca \
    --password-file ${STEPPATH}/ca.password.txt \
    --not-after 87660h \
    ${TMPDIR}/ica/${OUTFILE}.csr \
    ${STEPPATH}/certs/root_ca.crt \
    ${STEPPATH}/secrets/root_ca_key \

step certificate sign \
    --profile intermediate-ca \
    --password-file ${STEPPATH}/ca.password.txt \
    --not-after 87660h \
    ${TMPDIR}/ica/${OUTFILE}.csr \
    ${STEPPATH}/certs/root_ca.crt \
    ${STEPPATH}/secrets/root_ca_key \
    > ${TMPDIR}/ica/${OUTFILE}.crt
