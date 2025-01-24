#!/bin/sh

export STEPCAURL="https://ica.home.where-ever.za.net:443"
export STEPDIR=/usr/local/etc/step-ca
export STEPPATH=${STEPDIR}/ca
export CERTDIR=$STEPDIR/certs
export TMPDIR=$STEPDIR/tmp

# remove old
rm -rf $STEPPATH $TMPDIR


# create dirs
mkdir -p $TMPDIR
mkdir -p ${STEPPATH}/certs ${STEPPATH}/secrets ${STEPPATH}/db ${STEPPATH}/config
mkdir -p ${STEPPATH}/templates/ssh
mkdir -p ${STEPPATH}/templates/certs
mkdir -p $TMPDIR/root
mkdir -p $TMPDIR/intermediate
mkdir -p $TMPDIR/ica
mkdir -p $TMPDIR/cert

[ ! -f ${STEPDIR}/ca.password.txt ] && \
    openssl rand -hex 32 >  ${STEPDIR}/ca.password.txt
[ ! -f ${STEPDIR}/provisioner.password.txt ] && \
    openssl rand -hex 32 >  ${STEPDIR}/provisioner.password.txt

# Root ca cert template
cat > $STEPPATH/templates/root.tpl <<EOF
{
    "subject": {
        "country": "ZA",
        "organization": "Where-ever Home",
        "commonName": "Where-ever Home Root CA (2025)"
    },
    "issuer": {
        "country": "ZA",
        "organization": "Where-ever Home",
        "commonName": "Where-ever Home Root CA (2025)"
    },
    "keyUsage": ["certSign", "crlSign"],
    "basicConstraints": {
        "isCA": true,
        "maxPathLen": 3
    }
}
EOF

# Intermediate ca cert template
cat > $STEPPATH/templates/intermediate-1.tpl <<EOF
{
    "subject": {
        "country": "ZA",
        "organization": "Where-ever Home",
        "commonName": "Where-ever Home Intermediate CA (2025)"
    },
    "keyUsage": ["certSign", "crlSign"],
    "basicConstraints": {
        "isCA": true,
        "maxPathLen": 2
    },
    "crlDistributionPoints": ["${STEPCAURL}"]
}
EOF

# Create root key with higher maxpathlen
step certificate create \
    --template ${STEPPATH}/templates/root.tpl \
    "Where-ever Root CA (2025)" \
    $TMPDIR/root/root.crt \
    $TMPDIR/root/root.key \
    --not-after="262800h" \
    --password-file=${STEPDIR}/ca.password.txt

cp $TMPDIR/root/root.key ${STEPPATH}/secrets/root_ca_key 

# Init CA, 1st time
step ca init \
    --root=$TMPDIR/root/root.crt \
    --key=$TMPDIR/root/root.key \
    --key-password-file=${STEPDIR}/ca.password.txt \
    --acme \
    --ssh \
    --name="Where-ever Root CA (2025)" \
    --address=0.0.0.0:8443 \
    --dns=ca.home.where-ever.za.net \
    --deployment-type=standalone \
    --provisioner=vikashb@where-ever.za.net \
    --password-file ${STEPDIR}/ca.password.txt \
    --provisioner-password-file ${STEPDIR}/provisioner.password.txt

echo "removing initial intermediate ca"
rm -f ${STEPPATH}/certs/intermediate_ca.crt
rm -f ${STEPPATH}/secrets/intermediate_ca_key

# create new Intermediate CA
step certificate create "Where-ever Intermediate CA (2025)" \
    $TMPDIR/intermediate/intermediate_ca.csr \
    ${STEPPATH}/secrets/intermediate_ca_key \
    --csr \
    --template ${STEPPATH}/templates/intermediate-1.tpl \
    --password-file ${STEPDIR}/ca.password.txt

# sign new Intermediate
step certificate sign \
    $TMPDIR/intermediate/intermediate_ca.csr \
    ${STEPPATH}/certs/root_ca.crt \
    ${STEPPATH}/secrets/root_ca_key \
    --template ${STEPPATH}/templates/intermediate-1.tpl \
    --password-file ${STEPDIR}/ca.password.txt \
    --not-after 87660h \
    > ${STEPPATH}/certs/intermediate_ca.crt

echo "signed intermediate_ca crt"
openssl x509 -noout -text -in ${STEPPATH}/certs/intermediate_ca.crt

cp ${STEPDIR}/provisioner.password.txt \
   ${STEPDIR}/ca.password.txt \
   ${STEPPATH}/

# root fingerprint
echo "root ca fingerprint"
step certificate fingerprint ${STEPPATH}/certs/root_ca.crt

# intermediate fingerprint
echo "intermediate ca fingerprint"
step certificate fingerprint ${STEPPATH}/certs/intermediate_ca.crt

#service step-ca start

#step certificate install /usr/local/etc/step/ca/certs/root_ca.crt

# create a cert
cat <<EOT
step ca certificate \
    --san test.home.where-ever.za.net \
    --san 127.0.0.1 \
    --ca-url ${STEPCAURL} \
    --provisioner=vikashb@where-ever.za.net \
    --provisioner-password-file ${STEPDIR}/provisioner.txt \
  test test.crt test.key
EOT

cat <<EOT
update ca.json

        "insecureAddress": ":8080",
        "crl": {
                "enabled": true,
                "idpURL": "http://${STEPCAURL}/crl"
        },

part of authority block
                "claims": {
                        "minTLSCertDuration": "2160h0m0s",
                        "maxTLSCertDuration": "17520h0m0s",
                        "defaultTLSCertDuration": "8760h0m0s",
                        "minUserSSHCertDuration": "24m0s",
                        "maxUserSSHCertDuration": "96h0m0s",
                        "defaultUserSSHCertDuration": "16h0m0s",
                        "minHostSSHCertDuration": "5m0s",
                        "maxHostSSHCertDuration": "1680h0m0s",
                        "defaultHostSSHCertDuration": "17520h0m0s",
                        "disableRenewal": false,
                        "allowRenewalAfterExpiry": false
                },
                "backdate": "1m0s",

rm -rf $TMPDIR
