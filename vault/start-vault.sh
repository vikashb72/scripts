#!/usr/bin/env bash

unseal_vault() {
    [ ! -f ~/.vault.init.keys ] && \
    echo "missing ~/.vault.init.keys" && \
    exit 2

    echo "Unsealing Vault"
    VAULT_UNSEAL_KEYS=$(jq -r ".unseal_keys_b64[]" ~/.vault.init.keys | head -n 3)
    for VAULT_UNSEAL_KEY in $VAULT_UNSEAL_KEYS
    do
        vault operator unseal $VAULT_UNSEAL_KEY
    done
}

initialise_vault() {
    echo "Clean Vault Install - starting initialization."
    vault operator init -format=json > ~/.vault.init.keys
    unseal_vault
    sleep 5
    bash -x ./setup-vault.sh
}

# Check if vault is initialized
VAULT_STATUS=$(vault status -format=json | jq -r '.initialized')

if [[ -z "$VAULT_STATUS" ]]; then
    echo "Error: Vault status could not be retrieved"
    exit 1
fi

if [[ "$VAULT_STATUS" != "true" && "$VAULT_STATUS" != "false" ]]; then
    echo -e "Error: Vault status could not be retrieved.\n$VAULT_STATUS"
    exit 1
fi

if [[ "$VAULT_STATUS" == "false" ]]; then

    initialise_vault
fi

VAULT_STATUS=$(vault status -format=json | jq -r '.sealed')

if [[ -z "$VAULT_STATUS" ]]; then
    echo "Error: Vault status could not be retrieved"
    exit 1
fi

if [[ "$VAULT_STATUS" != "true" && "$VAULT_STATUS" != "false" ]]; then
    echo -e "Error: Vault status could not be retrieved.\n$VAULT_STATUS"
    exit 1
fi

if [[ "$VAULT_STATUS" == "true" ]]; then
    unseal_vault
fi
