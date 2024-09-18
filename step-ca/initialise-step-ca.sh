#!/bin/sh

export STEPDIR=/usr/local/etc/step
export STEPPATH=${STEPDIR}/ca

[ ! -f ${STEPDIR}/password.txt ] && uuidgen -r >  ${STEPDIR}/password.txt
[ ! -f ${STEPDIR}/provisioner.txt ] && uuidgen -r >  ${STEPDIR}/provisioner.txt

cat > $STEPPATH/intermediate.tpl <<EOF
{
    "subject": {{ toJson .Subject }},
    "keyUsage": ["certSign", "crlSign"],
    "basicConstraints": {
        "isCA": true,
        "maxPathLen": 0
    },
    "crlDistributionPoints":
        ["http://ca.home.where-ever.za.net/crl/ca.crl"]
    }
}
EOF

step ca init \
    --acme \
    --ssh \
    --name "Where Ever Root CA" \
    --dns=ca.home.where-ever.za.net \
    --address=192.168.0.5:8443 \
    --deployment-type=standalone \
    --provisioner=vikashb@where-ever.za.net \
    --password-file ${STEPDIR}/password.txt \
    --provisioner=vikashb@where-ever.za.net \
    --provisioner-password-file ${STEPDIR}/provisioner.txt \
     > step-ca.init.log 2>&1

#    --remote-management \
#    --admin-subject="Where-Ever Root CA" \

ROOT_FINGERPRINT=$(grep 'Root fingerprint' step-ca.init.log | awk '{ print $4}')
echo $ROOT_FINGERPRINT > ${STEPDIR}/root.fingerprint.txt
service step-ca start

step certificate install /usr/local/etc/step/ca/certs/root_ca.crt

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
