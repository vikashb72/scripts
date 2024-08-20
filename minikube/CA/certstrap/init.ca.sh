#!/usr/bin/env bash

rm -rf rootCA intermediateCA certs
mkdir rootCA intermediateCA certs

SSL_C="ZA"
SSL_ST="Gauteng"
SSL_L="Johannesburg"
SSL_O="Where-Ever"
SSL_OU="Where-Ever Minikube Lab"

ROOT_CN="${SSL_OU} Root CA"
INTERMEDIATE_CN="${SSL_OU} Intermediate CA"
ROOT_CA_PASSPHRASE="Assume-Ignorant-Dedicate-Quantity-Strain-Pin-Jungle"
INTERMEDIATE_CA_PASSPHRASE="Ward-Economics-Producer-Interface-Eternal-Abundant"

# Create root CA certificate
certstrap --depot-path certs init \
    --key-bits 4096 \
    --organization "${SSL_O}" \
    --organizational-unit "${SSL_OU}" \
    --country "${SSL_C}" \
    --province "${SSL_ST}" \
    --locality "${SSL_L}" \
    --common-name "${ROOT_CN}" \
    --expires "20 year" \
    --passphrase  "${ROOT_CA_PASSPHRASE}"

cp certs/*Root_CA* rootCA/
# Request and sign intermediate CA certificate
certstrap --depot-path certs \
    request-cert \
    --key-bits 4096 \
    --organization "${SSL_O}" \
    --organizational-unit "${SSL_OU}" \
    --country "${SSL_C}" \
    --province "${SSL_ST}" \
    --locality "${SSL_L}" \
    --common-name "${INTERMEDIATE_CN}" \
    --passphrase  "${INTERMEDIATE_CA_PASSPHRASE}"

certstrap --depot-path certs sign \
    "${INTERMEDIATE_CN}" \
    --CA "${ROOT_CN}" \
    --passphrase  "${ROOT_CA_PASSPHRASE}" \
    --expires "15 years" \
    --intermediate

cp certs/*Intermediate_CA* intermediateCA/

# Request and sign final client certificate without passphrase
DOMAIN="test.home.local"
certstrap --depot-path certs \
    request-cert \
    --organization "${SSL_O}" \
    --organizational-unit "${SSL_OU}" \
    --country "${SSL_C}" \
    --province "${SSL_ST}" \
    --locality "${SSL_L}" \
    --common-name "${DOMAIN}" \
    --passphrase "" \
    --key-bits 2048 \
    --ip 127.0.0.1,192.168.0.21 \
    --domain "test.home.local,*.test.home.local"

#   --curve value                            Elliptic curve name. Must be one of P-384, P-521, Ed25519, P-224, P-256.
#   --uri value                              URI values to add as subject alt name (comma separated)

certstrap --depot-path certs \
    sign ${DOMAIN} \
    --CA "${INTERMEDIATE_CN}" \
    --passphrase  "${INTERMEDIATE_CA_PASSPHRASE}" \
    --expires "90 days"

