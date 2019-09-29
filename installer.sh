#!/bin/bash

DATADIR_PATH="~/.bitcoin/" # for linux user
# DATADIR_PATH="/mnt/c/Users/sylva/AppData/Roaming/Bitcoin/" # for windows user through WSL, don't forget to add your bitcoin* binaries path to WSL path
# DATADIR="-datadir=$DATADIR_PATH" # If your datadir is not configured inside your bitcoin.conf
DATADIR=""
# RPC_PASSWORD="-rpcpassword=YOUR_RPC_PASSWORD"
RPC_PASSWORD=""
BITCOIND_OPTION_NO_NETWORK="-maxconnections=0 -listenonion=0 -listen=0 -disablewallet -checkblocks=1" # -checkblocks=1" # -listen=0"
BITCOIND_OPTIONS="$DATADIR"
CLI_OPTIONS="$RPC_PASSWORD"
BITCOIN_CLI="bitcoin-cli"
BITCOIND="bitcoind"
# BITCOIN_CLI="bitcoin-cli.exe" # WSL users
# BITCOIND="bitcoind.exe" # WSL users

parse_json() {
  python -c 'import json,sys;print json.load(sys.stdin)['$1']["'$2'"]' 
}

parse_json_obj() {
  python -c 'import json,sys;print json.load(sys.stdin)["'$1'"]' 
}

array_length() {
  python -c 'import json,sys;print len(json.load(sys.stdin))' 
}

echo "********************************************************************************"
echo "*                                                                              *"
echo "*      Make sure you downloaded this script on BitcoinSocialSync.com           *"
echo "*    Verify the checksum against the signed one displayed on the website       *"
echo "*                                                                              *"
echo "*             This script will quickly setup your Bitcoin full node.           *"
echo "*                  /!\   This process is NOT trustless.  /!\                   *"
echo "*             But it relly only on single security assumption:                 *"
echo "*    All the participants are either lying or you can trust the result         *"
echo "*                                                                              *"
echo "********************************************************************************"

echo "You need to have installed Bitcoin-Core before continuing"
read -n1 -p "Ready to continue? [y/n]: " DONE
echo ""
if [ $DONE != "Y" ] && [ $DONE != "y" ]; then
  echo "You can download Bitcoin-Core at https://bitcoincore.org/en/download/"
  exit 1
fi

BLOCK_CANDIDATES=$(curl -s 'https://bitcoinsocialsync.com/api/blocksCandidates.json') 
len=$(echo $BLOCK_CANDIDATES | array_length)

echo "Choose the UTXO set date:"
for ((i = 0; i < len; i++))
do
  echo -n "    [$i] " 
  echo $BLOCK_CANDIDATES | parse_json $i blockCreationDate 
done
read -n1 -p "[0-N]: " CHOSEN_DATE
echo ""
echo -n "You have chosen to start synching manually after the block: "
HASH_SERIALIZED_SERVER=$(echo $BLOCK_CANDIDATES | parse_json $CHOSEN_DATE hashSerialized)
BLOCK_HEIGHT=$(echo $BLOCK_CANDIDATES | parse_json $CHOSEN_DATE blockHeight)
HASH_INVALIDATE=$(echo $BLOCK_CANDIDATES | parse_json $CHOSEN_DATE blockHashInvalidate)
echo $BLOCK_CANDIDATES | parse_json $CHOSEN_DATE blockHash

# Start downloading 
echo "Downloading utxo-set-$BLOCK_HEIGHT.tar.gz..."
if [ -f "utxo-set-$BLOCK_HEIGHT.tar.gz" ]; then
  echo "File already exist, skipping download"
else
  wget https://downloads.bitcoinsocialsync.com/utxo-set/utxo-set-$BLOCK_HEIGHT.tar.gz
fi
echo "Download finished"

# Verification of downloads

CHAINSTATE_INFO=$(curl -s "https://bitcoinsocialsync.com/api/files/utxo-set-$BLOCK_HEIGHT.tar.gz") 
CHAINSTATE_CHECKSUM=$(echo $CHAINSTATE_INFO | parse_json_obj checksum)
echo $CHAINSTATE_INFO | parse_json_obj signature > utxo.asc
echo "Verifying checksum for file utxo-set-$BLOCK_HEIGHT.tar.gz ..."
CHAINSTATE_CHECKSUM_LOCAL=$(sha256sum utxo-set-$BLOCK_HEIGHT.tar.gz | awk 'NF {print $1}')
if [ $CHAINSTATE_CHECKSUM_LOCAL != $CHAINSTATE_CHECKSUM ]; then
  echo "Invalid checksum for utxo-set-$BLOCK_HEIGHT.tar.gz"
  exit 1
else
  echo "Valid checksum for utxo-set-$BLOCK_HEIGHT.tar.gz"
fi

# Do PGP verify
echo "Download and import Public Key..."
if [ -f "pubkey.asc" ]; then
  echo "File already exist, skipping download"
else
  wget https://downloads.bitcoinsocialsync.com/pubkey.asc
fi
gpg --import pubkey.asc 
echo "2A7870AE91918365A7D27AFEB48A961FB79729A8:6:" | gpg --import-ownertrust
echo "Verifying signature for file utxo-set-$BLOCK_HEIGHT.tar.gz ..."
gpg --verify utxo.asc utxo-set-$BLOCK_HEIGHT.tar.gz &> /dev/null
if [ $? -eq 0 ]
then
    echo "Signature is valid for utxo-set-$BLOCK_HEIGHT.tar.gz"
else
    echo "Invalid signature for utxo-set-$BLOCK_HEIGHT.tar.gz"
    exit 1
fi

# Install 
if [ -d "$DATADIR_PATH"chainstate ]; then
  echo ""$DATADIR_PATH"chainstate directory already exist. Deleting..."
  rm -rf "$DATADIR_PATH"chainstate
  echo "chainstate deleted."
fi
if [ -d "$DATADIR_PATH"blocks ]; then
  echo ""$DATADIR_PATH"blocks directory already exist. Deleting..."
  rm -rf "$DATADIR_PATH"blocks
  echo "blocks deleted."
fi
echo "Extracting utxo-set-$BLOCK_HEIGHT.tar.gz to "$DATADIR_PATH"..."
tar -zxf utxo-set-$BLOCK_HEIGHT.tar.gz -C "$DATADIR_PATH"
echo "Extracting finished."

PRUNING=$(cat "$DATADIR_PATH"bitcoin.conf | grep prune)
if [ -z "$PRUNING" ]; then
  echo "Your node doesn't seems configured to accept a pruned blockchain, adding prune=1 to "$DATADIR_PATH"bitcoin.conf"
  echo "prune=1" >> "$DATADIR_PATH"bitcoin.conf
fi

echo "Launching bitcoind with initial import..."
$BITCOIND $BITCOIND_OPTIONS $BITCOIND_OPTION_NO_NETWORK &> bitcoind.log & # &> /dev/null &
BITCOIND_PID=$!
sleep 5m
echo "Invalidating auto import at $HASH_INVALIDATE..."
$BITCOIN_CLI $CLI_OPTIONS invalidateblock $HASH_INVALIDATE
echo "Invalidating finished."
echo "Calculate local hash_serialized value with gettxoutsetinfo..."
HASH_SERIALIZED=$($BITCOIN_CLI $CLI_OPTIONS gettxoutsetinfo | grep hash_serialized | awk -F\" 'NF {print $4}')
if [ -z "$HASH_SERIALIZED" ]; then
  echo "Error: can't parse hash_serialized_2"
  exit 2 
fi
echo "You've found the following serizalized hash for the utxo set:"
echo $HASH_SERIALIZED
echo "The trusted hash is:"
echo $HASH_SERIALIZED_SERVER
if [ $HASH_SERIALIZED_SERVER != $HASH_SERIALIZED ]; then
  echo " /!\ Something is wrong. The UTXO set hash doesn't match the one provided by the server and signed by the community. /!\ "
  echo "Shutting down bitcoind..."
  $BITCOIN_CLI $CLI_OPTIONS stop
  wait $BITCOIND_PID
  echo "Removing installed file before exit..."
  rm -rf "$DATADIR_PATH"chainstate
  rm -rf "$DATADIR_PATH"blocks
  exit 1
fi
echo "Both hashes are a match, continuing..."

echo "Reconsidering block hash $HASH_INVALIDATE..."
$BITCOIN_CLI $CLI_OPTIONS reconsiderblock $HASH_INVALIDATE
echo "Reconsidering finished."

echo "Stopping bitcoind..."
$BITCOIN_CLI $CLI_OPTIONS stop
wait $BITCOIND_PID
echo "bitcoind stopped."

# echo "Starting bitcoind..."
# $BITCOIND $BITCOIND_OPTIONS &> /dev/null &
# echo "bitcoind started in the background."


echo ""
echo "********************************************************************************"
echo "*                                                                              *"
echo "*                You're now running your own full node! GG!                    *"
echo "*                                                                              *"
echo "********************************************************************************"
