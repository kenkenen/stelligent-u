#!/bin/bash

## The code below is a modified version from the creation of Liu Weiyuan:
## https://levelup.gitconnected.com/aws-cli-automation-for-temporary-mfa-credentials-31853b1a8692

# This script will run the aws sts get-session-token command to generate a temporary token for AWS CLI authentication
# with MFA. The token is used to overwrite the credentials file with the new credentials, thus allowing access to aws
# resources via straight aws commands without the need of the --profile flag.

# Prerequisite: jq is used to parse JSON data. This needs to be installed prior to execution of the script.

# Variable declaration for aws directory and profile;
AWS_DIR="$HOME/.aws"
PROFILE=""

# Function for generating setup file.
generateSetupFile(){
  read -rp "Enter the Access Key ID: " AKEY
  case $AKEY in
    "")
      while [ -z "$AKEY" ]; do
        read -rp "Access Key ID must not be empty. Please enter a valid value: " AKEY
      done;;
    * )
      ;;
  esac
  read -rp "Enter the Secret Access Key: " SKEY
  case $SKEY in
    "")
      while [ -z "$SKEY" ]; do
        read -rp "Secret Access Key must not be empty. Please enter a valid value: " SKEY
      done;;
    * )
      ;;
  esac
  read -rp "Please input the ARN (e.g. \"arn:aws:iam::12345678:mfa/username\"): " ARN
  case $ARN in
    "")
      while [ -z "$ARN" ]; do
        read -rp "ARN must not be empty. Please enter a valid value: " ARN
      done;;
    * )
      ;;
  esac
  echo '{ "Credentials": { "AccessKeyId": "'"$AKEY"'", "SecretAccessKey": "'"$SKEY"'", "ARN": "'"$ARN"'" } }' > "$AWS_DIR/$SETUP_FILE"

  # The setup file is used to create or overwrite the credentials file.
  echo "[default]" > "$AWS_DIR"/credentials
  echo "aws_access_key_id = ""$(cat "$AWS_DIR"/"$SETUP_FILE" | jq -r '.Credentials.AccessKeyId')">> "$AWS_DIR"/credentials
  echo "aws_secret_access_key = ""$(cat "$AWS_DIR"/"$SETUP_FILE" | jq -r '.Credentials.SecretAccessKey')" >> "$AWS_DIR"/credentials
}

# Prompts for profile name. Uppercase is converted to lowercase to make it easier to code.
while [ -z "$PROFILE" ]; do
  read -rp "Please enter the profile name: " PROFILE
  case $PROFILE in
    "") read -rp "Profile can not be empty. Please enter a valid input: ";;
    * ) PROFILE=$(echo "$PROFILE" | tr '[:upper:]' '[:lower:]');
      ;;
  esac

  SETUP_FILE=".$PROFILE.initsetup"

  if [ ! -e "$AWS_DIR"/"$SETUP_FILE" ]; then
    read -rp "Is this a new profile? " RESPONSE
    case $RESPONSE in
      "y"|"Y"|"yes"|"Yes")
        generateSetupFile;;
      * )
        PROFILE="";;
    esac
  fi
done

# Variable declarations for AWS Token file.
AWS_TOKEN_FILE=".$PROFILE.awstoken"

# ARN is pulled from the setup file for the serial number parameter in the awscli command.
MFA_SERIAL=$(cat "$AWS_DIR"/"$SETUP_FILE" | jq -r '.Credentials.ARN')

# Function for generating a token using 'aws sts get-session-token' with the entered MFA pin and ARN from the setup file.
generateToken(){
# The setup file is used to overwrite the credentials file in order to remove stale credentials.
echo "[default]" > "$AWS_DIR"/credentials
echo "aws_access_key_id = ""$(cat "$AWS_DIR"/"$SETUP_FILE" | jq -r '.Credentials.AccessKeyId')">> "$AWS_DIR"/credentials
echo "aws_secret_access_key = ""$(cat "$AWS_DIR"/"$SETUP_FILE" | jq -r '.Credentials.SecretAccessKey')" >> "$AWS_DIR"/credentials

# Prompts the user for the 6 digit MFA code.
  while true; do
    read -rp "Please enter the 6 digit code from your MFA device: " mfa_auth
    case $mfa_auth in
      [0-9][0-9][0-9][0-9][0-9][0-9] ) MFA_CODE=$mfa_auth; break;;
      * ) echo "Please enter a valid 6 digit code." ;;
    esac
  done

# Variable declared for the awscli command
authOutput=$(aws sts get-session-token --serial-number "$MFA_SERIAL" --token-code "$MFA_CODE")

# awscli command is executed via echo and the auth token is saved to a file.
echo "$authOutput" > "$AWS_DIR"/"$AWS_TOKEN_FILE"

# Dump the authentication into the credentials file if the token was generated
if [ -e "$AWS_DIR"/"$AWS_TOKEN_FILE" ]; then
  echo "[default]" > "$AWS_DIR"/credentials
  echo "aws_access_key_id = ""$(cat "$AWS_DIR"/"$AWS_TOKEN_FILE" | jq -r '.Credentials.AccessKeyId')">> "$AWS_DIR"/credentials
  echo "aws_secret_access_key = ""$(cat "$AWS_DIR"/"$AWS_TOKEN_FILE" | jq -r '.Credentials.SecretAccessKey')" >> "$AWS_DIR"/credentials
  echo "aws_session_token = ""$(cat "$AWS_DIR"/"$AWS_TOKEN_FILE" | jq -r '.Credentials.SessionToken')" >> "$AWS_DIR"/credentials
fi
}

# If the token is already present, it is retrieved from the file, else invoke generateToken
if [ -e "$AWS_DIR"/"$AWS_TOKEN_FILE" ]; then
  authOutput=$(cat "$AWS_DIR"/"$AWS_TOKEN_FILE")
  authExpiry=$(echo "$authOutput" | jq -r '.Credentials.Expiration')
  nowTime=$(date -u +'%Y-%m-%dT%H:%M:%SZ')

  # Checks the expiration value against the current time. If expiry is passed, generateToken is invoked. If the token is
  # still valid, exits with a printed message. Otherwise, generateToken is invoked.
  if [ "$authExpiry" \< "$nowTime" ]; then
    echo "Your token has expired and must be renewed"
    generateToken
  else
    echo "Your token is still valid"
    echo "[default]" > "$AWS_DIR"/credentials
    echo "aws_access_key_id = ""$(cat "$AWS_DIR"/"$AWS_TOKEN_FILE" | jq -r '.Credentials.AccessKeyId')">> "$AWS_DIR"/credentials
    echo "aws_secret_access_key = ""$(cat "$AWS_DIR"/"$AWS_TOKEN_FILE" | jq -r '.Credentials.SecretAccessKey')" >> "$AWS_DIR"/credentials
    echo "aws_session_token = ""$(cat "$AWS_DIR"/"$AWS_TOKEN_FILE" | jq -r '.Credentials.SessionToken')" >> "$AWS_DIR"/credentials
    exit 0;
  fi
else
  generateToken
fi

# Values can be sourced from these variables.
# AWS_ACCESS_KEY_ID=`echo ${authOutput} | jq -r '.Credentials.AccessKeyId'`
# AWS_SECRET_ACCESS_KEY=`echo ${authOutput} | jq -r '.Credentials.SecretAccessKey'`
# AWS_SESSION_TOKEN=`echo ${authOutput} | jq -r '.Credentials.SessionToken'`