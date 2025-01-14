#!/bin/sh

export STEPDIR=/usr/local/etc/step
export STEPPATH=${STEPDIR}/ca
rm -rf $STEPPATH

[ ! -f ${STEPDIR}/password.txt ] && uuidgen -r >  ${STEPDIR}/password.txt
[ ! -f ${STEPDIR}/provisioner.txt ] && uuidgen -r >  ${STEPDIR}/provisioner.txt

rm -f intermediate_ca.csr

# Init CA, 1st time
step ca init \
    --acme \
    --ssh \
    --name "Where Ever Root CA (2025)" \
    --dns=ca.home.where-ever.za.net \
    --address=192.168.0.3:8443 \
    --deployment-type=standalone \
    --provisioner=vikashb@where-ever.za.net \
    --password-file ${STEPDIR}/password.txt \
    --provisioner=vikashb@where-ever.za.net \
    --provisioner-password-file ${STEPDIR}/password.txt 

# Root cert template
cat > $STEPPATH/templates/root.tpl <<EOF
{
    "subject": {
        "country": "ZA",
        "organization": "Where-ever Home",
        "commonName": "Where Ever Home Root CA (2025)"
    },
    "issuer": {
        "country": "ZA",
        "organization": "Where-ever Home",
        "commonName": "Where Ever Home Root CA (2025)"
    },
    "keyUsage": ["certSign", "crlSign"],
    "basicConstraints": {
        "isCA": true,
        "maxPathLen": 4
    }
}
EOF

# Intermediate key template
cat > $STEPPATH/intermediate.tpl <<EOF
{
    "subject": {
        "country": "ZA",
        "organization": "Where-ever Home",
        "commonName": "Where Ever Home Intermediate CA (2025)"
    },
    "keyUsage": ["certSign", "crlSign"],
    "basicConstraints": {
        "isCA": true,
        "maxPathLen": 3
    },
    "crlDistributionPoints": ["http://ca.home.where-ever.za.net/crl"]
}
EOF

echo "Initial root ca"
openssl x509 -noout -text -in ${STEPPATH}/certs/root_ca.crt

rm -f ${STEPPATH}/certs/root_ca.crt
rm -f ${STEPPATH}/secrets/root_ca_key

# Create root key (replace current)
step certificate create \
    --template ${STEPPATH}/templates/root.tpl \
    "Where Ever Root CA (2025)" \
    ${STEPPATH}/certs/root_ca.crt \
    ${STEPPATH}/secrets/root_ca_key \
    --not-after="262800h" \
    --password-file=password.txt

echo "regenerated root ca"
openssl x509 -noout -text -in ${STEPPATH}/certs/root_ca.crt

echo "initial intermediate_ca"
openssl x509 -noout -text -in ${STEPPATH}/certs/intermediate_ca.crt
rm -f ${STEPPATH}/certs/intermediate_ca.crt
rm -f ${STEPPATH}/secrets/intermediate_ca_key

step certificate create "Where Ever Intermediate CA (2025)" \
    intermediate_ca.csr \
    ${STEPPATH}/secrets/intermediate_ca_key \
    --csr \
    --template ${STEPPATH}/intermediate.tpl \
    --password-file password.txt \

echo "intermediate_ca csr"
openssl req -noout -text -in intermediate_ca.csr

step certificate sign \
    intermediate_ca.csr \
    ${STEPPATH}/certs/root_ca.crt \
    ${STEPPATH}/secrets/root_ca_key \
    --template ${STEPPATH}/intermediate.tpl \
    --password-file password.txt \
    --not-after 87660h \
    > ${STEPPATH}/certs/intermediate_ca.crt

echo "signed intermediate_ca crt"
openssl x509 -noout -text -in ${STEPPATH}/certs/intermediate_ca.crt


exit
ROOT_FINGERPRINT=$(grep 'Root fingerprint' step-ca.init.log | awk '{ print $4}')
echo $ROOT_FINGERPRINT > ${STEPDIR}/root.fingerprint.txt
#service step-ca start

#step certificate install /usr/local/etc/step/ca/certs/root_ca.crt

exit

# create a cert
step ca certificate \
    --san hashicorp-vault.home.where-ever.za.net \
    --san vault.home.where-ever.za.net \
    --san 127.0.0.1 \
    --san 192.168.0.22 \
    --ca-url https://ca.home.where-ever.za.net:8443 \
    --provisioner=vikashb@where-ever.za.net \
    --provisioner-password-file ${STEPDIR}/provisioner.txt \
  vault vault.home.where-ever.za.net.crt vault.home.where-ever.za.net.key
