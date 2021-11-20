#!/bin/bash

## Parts of this code were obtained from Liu Weiyuan:
## https://levelup.gitconnected.com/aws-cli-automation-for-temporary-mfa-credentials-31853b1a8692

# Copyright (c) 2021 by Kenny Tejeda
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# This script facilitates profile switching for the aws cli with or without MFA. It will run the aws sts
# get-session-token command to generate a temporary token for AWS CLI authentication with MFA. The token is used to
# overwrite the credentials file with the new credentials, thus allowing access to aws resources via straight aws cli
# commands without the need of the --profile flag.

# Prerequisite: jq is used to parse JSON data. This needs to be installed prior to execution of the script.

# Variable declaration for aws directory, profile, setup file, and MFA authentication code. The profile and MFA auth
# accept parameters 1 and 2 respectively;
AWS_DIR="$HOME/.aws"
PROFILE="$1"
SETUP_FILE=".$PROFILE.initsetup"
MFA_AUTH="$2"

# Checks that a valid 6 digit pin was entered. Ignored if null.
while true; do
  case $MFA_AUTH in
    "" ) break;;
    [0-9][0-9][0-9][0-9][0-9][0-9] ) MFA_CODE=$MFA_AUTH; break;;
    *  ) read -rp "Please enter a valid 6 digit code: " MFA_AUTH ;;
  esac
done

# Function for generating setup file. Access Key ID, Secret Access Key, and the ARN are stored into variables which are
# then used to create the setup file via echo.
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
  read -rp "Please input the ARN if MFA is in use(e.g. \"arn:aws:iam::12345678:mfa/username\"): " ARN

  echo '{ "Credentials": { "AccessKeyId": "'"$AKEY"'", "SecretAccessKey": "'"$SKEY"'", "ARN": "'"$ARN"'" } }' > "$AWS_DIR/$SETUP_FILE"
}

# Variable declaration for setup file.
SETUP_FILE=".$PROFILE.initsetup"

# Checks that a setup file exists. If not, prompts the user to verify new profile. If answered yes, generateSetupFile is
# invoked. Otherwise, PROFILE is blanked and user is prompted to enter a new profile. Another check for the setup file
# will repeat the loop.
while [ ! -e "$AWS_DIR"/"$SETUP_FILE" ]; do
  read -rp "No setup file exists. Is this a new profile? " RESPONSE
  case $RESPONSE in
    "y"|"Y"|"yes"|"Yes")
      generateSetupFile;
      break;;
    * )
      ;;
  esac
  read -rp "Please enter the profile name: " PROFILE
  case $PROFILE in
    "") read -rp "Profile can not be empty. Please enter a valid input: ";;
    * ) PROFILE=$(echo "$PROFILE" | tr '[:upper:]' '[:lower:]');
        SETUP_FILE=".$PROFILE.initsetup";
      ;;
  esac
done

# The setup file is used to create or overwrite the credentials file.
echo "[default]" > "$AWS_DIR"/credentials
echo "aws_access_key_id = ""$(jq -r '.Credentials.AccessKeyId' "$AWS_DIR"/"$SETUP_FILE")">> "$AWS_DIR"/credentials
echo "aws_secret_access_key = ""$(jq -r '.Credentials.SecretAccessKey' "$AWS_DIR"/"$SETUP_FILE")" >> "$AWS_DIR"/credentials

# Variable declarations for AWS Token file.
AWS_TOKEN_FILE=".$PROFILE.awstoken"

# ARN is pulled from the setup file for the serial number parameter in the awscli command.
MFA_SERIAL=$(jq -r '.Credentials.ARN' "$AWS_DIR"/"$SETUP_FILE")

# Function for generating a token using 'aws sts get-session-token' with the entered MFA pin and ARN from the setup file.
generateToken(){
# The setup file is used to overwrite the credentials file in order to remove stale credentials.
echo "[default]" > "$AWS_DIR"/credentials
echo "aws_access_key_id = ""$(jq -r '.Credentials.AccessKeyId' "$AWS_DIR"/"$SETUP_FILE")">> "$AWS_DIR"/credentials
echo "aws_secret_access_key = ""$(jq -r '.Credentials.SecretAccessKey' "$AWS_DIR"/"$SETUP_FILE")" >> "$AWS_DIR"/credentials

# Prompts the user for the 6 digit MFA code.
if [ -z "$MFA_CODE" ]; then
  while true; do
    read -rp "Please enter the 6 digit code from your MFA device: " mfa_auth
    case $mfa_auth in
      [0-9][0-9][0-9][0-9][0-9][0-9] ) MFA_CODE=$mfa_auth; break;;
      * ) echo "Please enter a valid 6 digit code." ;;
    esac
  done
fi

# Variable declared for the awscli command
authOutput=$(aws sts get-session-token --serial-number "$MFA_SERIAL" --token-code "$MFA_CODE")


# awscli command is executed via echo and the auth token is saved to a file.
echo "$authOutput" > "$AWS_DIR"/"$AWS_TOKEN_FILE"

# Dump the authentication into the credentials file if the token was generated
if [ -e "$AWS_DIR"/"$AWS_TOKEN_FILE" ]; then
  echo "[default]" > "$AWS_DIR"/credentials;
  {
    echo "aws_access_key_id = ""$(jq -r '.Credentials.AccessKeyId' "$AWS_DIR"/"$AWS_TOKEN_FILE")";
    echo "aws_secret_access_key = ""$(jq -r '.Credentials.SecretAccessKey' "$AWS_DIR"/"$AWS_TOKEN_FILE")";
    echo "aws_session_token = ""$(jq -r '.Credentials.SessionToken' "$AWS_DIR"/"$AWS_TOKEN_FILE")";
  } >> "$AWS_DIR"/credentials
fi
}

# If ARN is blank, delete any token file that exists for this profile.
if [ -z "$(jq -r '.Credentials.ARN' "$AWS_DIR"/"$SETUP_FILE")" ]; then
  if [ -e "$AWS_DIR"/"$AWS_TOKEN_FILE" ]; then
    rm "$AWS_DIR"/"$AWS_TOKEN_FILE"
  fi
fi

# If the token exists, data is passed to authOutput, else invoke generateToken
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
    echo "Your token is still valid."
    echo "[default]" > "$AWS_DIR"/credentials
    {
      echo "aws_access_key_id = ""$(jq -r '.Credentials.AccessKeyId' "$AWS_DIR"/"$AWS_TOKEN_FILE")";
      echo "aws_secret_access_key = ""$(jq -r '.Credentials.SecretAccessKey' "$AWS_DIR"/"$AWS_TOKEN_FILE")";
      echo "aws_session_token = ""$(jq -r '.Credentials.SessionToken' "$AWS_DIR"/"$AWS_TOKEN_FILE")";
    } >> "$AWS_DIR"/credentials
    echo "Credentials applied successfully!"
    exit 0;
  fi
else
  if [ -z "$(jq -r '.Credentials.ARN' "$AWS_DIR"/"$SETUP_FILE")" ]; then
    echo "Credentials applied successfully!"
    exit 0;
  else
    generateToken
  fi
fi

# Values can be sourced from these variables.
# AWS_ACCESS_KEY_ID=`echo ${authOutput} | jq -r '.Credentials.AccessKeyId'`
# AWS_SECRET_ACCESS_KEY=`echo ${authOutput} | jq -r '.Credentials.SecretAccessKey'`
# AWS_SESSION_TOKEN=`echo ${authOutput} | jq -r '.Credentials.SessionToken'`