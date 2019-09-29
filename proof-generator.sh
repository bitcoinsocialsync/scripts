#!/bin/bash

DATADIR=""
# RPC_PASSWORD="-rpcpassword=YOUR_RPC_PASSWORD"
RPC_PASSWORD=""
BITCOIN_CLI="bitcoin-cli"
# BITCOIN_CLI="bitcoin-cli.exe" # WSL users
CLI_OPTIONS="$RPC_PASSWORD"

parse_json() {
  python -c 'import json,sys;print json.load(sys.stdin)['$1']["'$2'"]' 
}

array_length() {
  python -c 'import json,sys;print len(json.load(sys.stdin))' 
}

echo "********************************************************************************"
echo "*                                                                              *"
echo "*      Make sure you downloaded this script on BitcoinSocialSync.com           *"
echo "*    Verify the checksum against the signed one displayed on the website       *"
echo "*                                                                              *"
echo "*                                                                              *"
echo "*          First, you need to register your fingerprint on Twitter             *"
echo "*                       otherwise this script will fail!                       *"
echo "*                                                                              *"
echo "*                   @BitcoinSync register MY_PGP_FINGERPRINT                   *"
echo "*                                                                              *"
echo "*                then go to https://bitcoinsocialsync.com/pubkey               *"
echo "*                     and publish the associated PGP PubKey                    *"
echo "*                                                                              *"
echo "********************************************************************************"

read -n1 -p "Ready to continue? [y/n]: " DONE
echo ""
if [ $DONE != "Y" ] && [ $DONE != "y" ]; then
  echo "Before being able to sign proofs you need to register your PGP Fingerprint on Twitter & publish your PGP PubKey on https://bitcoinsocialsync.com/pubkey"
  exit 1
fi

read -p "Enter your Twitter handle: " TWITTER_NAME
if [ $TWITTER_NAME = "" ]; then
  echo "Error: you must specify your Twitter handle"
  exit 2 
fi

BLOCK_CANDIDATES=$(curl -s 'https://bitcoinsocialsync.com/api/blocksCandidates.json') 
len=$(echo $BLOCK_CANDIDATES | array_length)

echo "Choose a date to create the proof from:"
for ((i = 0; i < len; i++))
do
  echo -n "    [$i] " 
  echo $BLOCK_CANDIDATES | parse_json $i blockCreationDate 
done
read -n1 -p "[0-N]: " CHOSEN_DATE
echo ""
echo -n "You have chosen to create your proof for the block: "
echo $BLOCK_CANDIDATES | parse_json $CHOSEN_DATE blockHash
BLOCK_HASH_INVALIDATE=$(echo $BLOCK_CANDIDATES | parse_json $CHOSEN_DATE blockHashInvalidate)
HASH_SERIALIZED_SERVER=$(echo $BLOCK_CANDIDATES | parse_json $CHOSEN_DATE hashSerialized)
BLOCK_HEIGHT=$(echo $BLOCK_CANDIDATES | parse_json $CHOSEN_DATE blockHeight)
 
# Rewinding node
echo "Node is rewinding to blockHeight: $BLOCK_HEIGHT"
echo "This will take at least a few minutes..."
$BITCOIN_CLI $CLI_OPTIONS invalidateblock $BLOCK_HASH_INVALIDATE
echo "Rewinding finished."

# Signing
echo "Calculate local hash_serialized value with gettxoutsetinfo..."
HASH_SERIALIZED=$($BITCOIN_CLI $CLI_OPTIONS gettxoutsetinfo | grep hash_serialized | awk -F\" 'NF {print $4}')
if [ -z "$HASH_SERIALIZED" ]; then
  echo "Error: can't parse hash_serialized_2"
  exit 2 
fi
echo "You've found the following serizalized hash for the utxo set: $HASH_SERIALIZED"
echo "The hash from the server is the following: $HASH_SERIALIZED_SERVER"
if [ $HASH_SERIALIZED_SERVER = $HASH_SERIALIZED ]; then
  echo "You need to sign the following message with PGP: "
  echo "BitcoinSocialSync.com: $BLOCK_HEIGHT $HASH_SERIALIZED"
  echo "BitcoinSocialSync.com: $BLOCK_HEIGHT $HASH_SERIALIZED" | gpg --clearsign -a --output "$BLOCK_HEIGHT".bssproof
  echo "Proof generated:"
  cat "$BLOCK_HEIGHT".bssproof
  PROOF=$(cat "$BLOCK_HEIGHT".bssproof)
  echo "This proof has been stored in "$BLOCK_HEIGHT".bssproof"

  echo "Uploading proof to server..."
  CURL_RESULT=$(curl -s -o /dev/null -w "%{http_code}" -d "twitterName=$TWITTER_NAME" --data-urlencode "proof=$PROOF" -X POST https://bitcoinsocialsync.com/api/users/proof)
  echo ""
  if [ $CURL_RESULT != "400" ]; then
    echo "Proof Uploaded: https://bitcoinsocialsync.com/user/$TWITTER_NAME"
  else
    echo "The automatic upload of the proof failed."
    echo "Please go to https://bitcoinsocialsync.com/newProof to upload it manually."
  fi
else 
  echo "Something seems to be wrong with your node, are you on the valid Bitcoin blockchain?"
  exit 1
fi

# Revert node to normal
read -n1 -p "Do you want to revert your node to it's previous state? [y/n]: " DONE
echo ""
if [ $DONE = "Y" ] || [ $DONE = "y" ]; then
  echo "Reverting node to previous state."
  echo "This will take at least a few minutes..."
  $BITCOIN_CLI $CLI_OPTIONS reconsiderblock $BLOCK_HASH_INVALIDATE
  echo "Your node is back into it's previous state."
fi

echo ""
echo "********************************************************************************"
echo "*                                                                              *"
echo "*  Thank you for participating in helping the community sync their full node!  *"
echo "*                                                                              *"
echo "********************************************************************************"