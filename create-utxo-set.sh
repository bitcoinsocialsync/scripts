#!/bin/bash
BLOCK="595000"
PRUNE="590000"
BLOCKHASH=$(bitcoin-cli.exe getblockhash $BLOCK)
bitcoin-cli.exe invalidateblock $BLOCKHASH
bitcoin-cli.exe pruneblockchain $PRUNE
bitcoin-cli.exe pruneaftertip
bitcoin-cli.exe stop
tar -czvf utxo-set-$BLOCK.tar.gz -C /mnt/d/crypto/bitcoin/chain/ chainstate/ -C /mnt/d/crypto/bitcoin/chain/ blocks/
sha256sum utxo-set-$BLOCK.tar.gz > $BLOCK.checksum
gpg --output $BLOCK.bssproof -a --detach-sig utxo-set-$BLOCK.tar.gz
# cat $BLOCK.checksum | keybase pgp sign -m 
bitcoin-cli.exe reconsiderblock $BLOCKHASH
# bitcoin-cli.exe stop