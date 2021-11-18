# Exercise 0.1.1
This folder contains my attempts at completing exercise 0.1.1 from the 00-dev-environment module. Anything in scrap is
likely a failed attempt.

# 21/11/15 - 2:12PM EST

Looks like my attempt at a crib of Liu Weiyuan was unsuccessful:

https://levelup.gitconnected.com/aws-cli-automation-for-temporary-mfa-credentials-31853b1a8692

I did not get the results I expected from repeated attempts to run the scripts he published. I'll have to start from
scratch at this point, unless I find another published script that achieves the same results.

AWS Docs on accessing AWS CLI using MFA:

https://aws.amazon.com/premiumsupport/knowledge-center/authenticate-mfa-cli/

# 21/11/16 - 12:17PM EST

I found that the reason the scripts (mfacredretrieval.sh and onetimesetup.sh) from Liu didn't work was because I had 
changed the shell to zsh. After reverting to bash it worked fine. After having understood the concept of the script he 
wrote, I decided to write my own. Since all that is happening here, is the gathering of input for each component of the 
awscli string indicated in the link above then writing a basic script for this should be simple. Liu's script adds 
functionality that works great as a solution for ease of use with MFA. I'll try to build some of that functionality into 
my script from scratch. What the script must accomplish:

1. Run the sts get-session-token AWS cli command:
   1. aws sts get-session-token --serial-number arn-of-the-mfa-device --token-code code-from-token
2. arn-of-the-mfa-device should be pulled from a previously stored location
3. code-from-token should be pulled from input stored in a variable
4. Output should be saved to a token file.

# 21/11/16 - 3:20PM EST

I completed the script stsgst.sh. I relied heavily on the work of Liu Weiyuan. As it stands, I combined the one time
setup script Liu made for initially setting the ARN with the script for generating the token. It creates the tmp_dir,
.mfaserial, and .awstoken files successfully. I modified variable names to my liking but, aside from the combination of
the two scripts, which required some of my own creation, it remains mostly identical to Liu Weiyuan's work. With the
token generated, I now need to figure out how to use it in conjuction with awscli. Liu used an npm script and sourced
the scripts I just created.

# 21/11/16 - 6:46PM EST

I completed the script stsgst.sh (again). This time, it outputs the credentials directly to the .aws/credentials file
used for authentication when connecting to aws via awscli. Now all I need to do is test to see if it works for
authentication.

# 21/11/17 - 11:29 AM

Great success! After running the script this morning, I hit a snag. There was an issue with te way I wrote the script
that caused an expired token to break everything. The expired token would invoke the function but because the expired
session token remained in the credentials file, the awscli command would fail and the credentials file would then be
filled with blank credentials, causing the whole thing to break for sure. Luckily, I had saved the secret access key
when I had created it or I would have to generate a new pair.

I modified the code and fixed the problem. Now a check is made for an existing token at the beginning of the function.
If it exists, the Access Key and Secret Access Key are both copied and then a new credentials file is created with these
assets. I also added a message for when the current token is not yet expired. 

After running the script, I tested with 'aws s3 ls' and it worked. I'll have to blow out the credentials and re-run
the script with a parameter for a very short expiry so that I can test and see what happens once a token is expired.

# 21/11/18 - 7:08 AM

I found out I could force the expiry of the token by just manually editing the time stamp for expiry in the awstoken
file that is generated. Easy testing.

I had to modify the code as several problems arose when the token was expired:
1. The credentials file would be filled with blank information whenever the awscli command failed.
2. The awscli command would fail because the access key id and secret key pulled from the awstoken file are only valid
   with the session token.

I had to make a major overhaul. I changed the MFA serial file to an initial setup file. The initial setup file is
generated from a series of prompts like was originally used for just the ARN, but this time, the Access Key ID, Secret
Access Key and ARN are prompted for. The values are used to generate a JSON. This JSON is used to create/overwrite the
credentials file whenever the script is run initially and subsequently whenever the token file is expired. This worked
without issue.

Success (for real this time)!!

In the future, I will be translating this script to python. For now, I'll move on to the next exercise.





