# Usage guide

Everyday operations: wallet, faucet, inscribing.

## Wallet

Once your node is funded, the `wallet` command sends transfers and inspects state via the node's built-in wallet API. All cryptography (signing, proof generation) happens inside the node — the CLI is a thin HTTP client.

```sh
# Show balance + note count for every known_key, with total
logosup wallet balance

# Per-note breakdown for one key
logosup wallet balance 793055d1...

# Send 100 to a recipient (auto-picks a funding key with sufficient balance)
logosup wallet transfer 8a3b7f...c2d1 100

# Explicit funding/change keys, skip the confirmation prompt
logosup wallet send 8a3b7f...c2d1 100 --from 793055d1... --change 62156fa0... --yes

# By default, leftover change returns to the funding key. Pass --change <key>
# only if you want it to land on a different address.

# Look up a transaction by hash (0x prefix optional)
logosup wallet tx 4d8e2a...
```

This is the **base-layer wallet** — the keys in `wallet.known_keys` of `user_config.yaml`, queried against `/wallet/{pk}/balance` and `/wallet/transactions/transfer-funds` on the node. The Logos Execution Zone (LEZ) wallet is a separate layer-2 wallet with its own account model, faucet, and binary — tracked separately ([#9](https://github.com/logosnode/logosup/issues/9)).

If the wallet endpoint times out (HTTP 408), the CLI surfaces the API's response inline so you can see why. Retry the same command — don't auto-script retries since each transfer attempt is its own HTTP submission.

### Tx-lookup limitation on v0.1.2

On testnet node v0.1.2, `wallet tx <hash>` may return 404 even for transactions that clearly landed (your balance updated). The wallet API hash and the public explorer's hash use different hashing schemes; the node's `/cryptarchia/transaction/<id>` endpoint was added in a release after v0.1.2. The most reliable confirmation today is to watch your `wallet balance` change — that's the source of truth.

Filed upstream: [explorer-template#15](https://github.com/logos-blockchain/logos-blockchain-block-explorer-template/issues/15).

## Faucet

```sh
logosup faucet
```

Displays your wallet keys (so you can pick which to fund), shows the faucet URL, and opens it in your browser if available. After requesting funds, wait ~3.5 hours for UTXO maturity before the node participates in consensus.

## Keys

```sh
logosup keys              # Show wallet keys
logosup keys backup       # Encrypted, password-protected export
logosup keys restore      # Restore from backup (interactive)
```

`keys backup` produces a passphrase-encrypted file you can safely store elsewhere; `keys restore` reads it back into a fresh install.

## Inscribing text

Publish text inscriptions on-chain via the node's text sequencer:

```sh
# Interactive — type lines, Enter inscribes each
logosup inscribe

# Pipe from stdin
echo "Hello World, from Lisbon Circle" | logosup inscribe -

# From a file
logosup inscribe - < message.txt
```

The sequencer creates a signing key (`sequencer.key`) and checkpoint file (`sequencer.checkpoint`) in the node data directory for crash recovery. These persist across restarts.
