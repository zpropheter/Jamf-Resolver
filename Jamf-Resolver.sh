#!/bin/bash

#Jamf-Resolver is designed to walk admins and end-users through resolutions to common issues. It starts with some of the most common issues and progresses into some of the more complex items from there

# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#        * Redistributions of source code must retain the above copyright
#         notice, this list of conditions and the following disclaimer.
#      * Redistributions in binary form must reproduce the above copyright
#           notice, this list of conditions and the following disclaimer in the
#           documentation and/or other materials provided with the distribution.
#         * Neither the name of the JAMF Software, LLC nor the
#           names of its contributors may be used to endorse or promote products
#           derived from this software without specific prior written permission.
# THIS SOFTWARE IS PROVIDED BY JAMF SOFTWARE, LLC "AS IS" AND ANY
# EXPRESSED OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL JAMF SOFTWARE, LLC BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#User defined Variables- set to 'TRUE' , 'FALSE' , or 'CAUTIOUS' to enable or disable each feature. 'CAUTIOUS' variable does read only and requires user intervention to remove files
JRR=TRUE
DSER=TRUE
APIUSER="API_Username"
APIPASS="API_password"
url="https://serverurl.jamfcloud.com"

#DEFINE WHERE YOU WANT RESULTS SAVED
output=/Users/Shared/output.txt

#HARD CODED VARIABLES
loggedInUser=$( echo "show State:/Users/ConsoleUser" | /usr/sbin/scutil | /usr/bin/awk '/Name :/ && ! /loginwindow/ { print $3 }' )
reconleftovers=$(ls /Library/Application\ Support/JAMF/tmp/)
Recon_Directory_Copy=/Users/Shared/
jamf_log=/private/var/log/jamf.log

#HARD CODED VARIABLE FOR API BEARER TOKEN RETRIEVAL
getBearerToken() {
	response=$(curl -s -u "$APIUSER":"$APIPASS" "$url"/api/v1/auth/token -X POST)
	bearerToken=$(echo "$response" | plutil -extract token raw -)
	tokenExpiration=$(echo "$response" | plutil -extract expires raw - | awk -F . '{print $1}')
	tokenExpirationEpoch=$(date -j -f "%Y-%m-%dT%T" "$tokenExpiration" +"%s")
}

#HARD CODED VARIABLE FOR API BEARER TOKEN INVALIDATION
invalidateToken() {
	responseCode=$(curl -w "%{http_code}" -H "Authorization: Bearer ${bearerToken}" $url/api/v1/auth/invalidate-token -X POST -s -o /dev/null)
	if [[ ${responseCode} == 204 ]]
	then
		echo "Token successfully invalidated"
		bearerToken=""
		tokenExpirationEpoch="0"
	elif [[ ${responseCode} == 401 ]]
	then
		echo "Token already invalid"
	else
		echo "An unknown error occurred invalidating the token" 
	fi
}

#Jamf_Recon_Resolver
#CHECK IF ENABLED
if [[ "$JRR" == TRUE ]];then
	#CHECK IF RECON FOLDER HAS ANY ITEMS IN IT
	if [[ $reconleftovers == "" ]]; then
		echo -e "Recon Folder Empty, we love to see that!\n" >> $output
	else
		echo -e "The following was found in the temporary Recon directory:\n$reconleftovers\nEmptying out the recon folder...\n" >> $output
		find /Library/Application\ Support/JAMF/tmp/ -type f -delete
		if [[ -e $reconverify ]];then
			echo -e "Unable to remove files from Recon directory\n" >> $output
		else
			echo -e "Files removed from recon directory\n" >> $output
		fi
	fi
#CHECK IF DISABLED
elif [[ "$JRR" == FALSE ]];then
	echo -e "Recon Recon Resolver turned off\n" >> $output
#CHECK IF SET TO READ ONLY
elif [[ "$JRR" == CAUTIOUS ]];then
	#CHECK IF RECON FOLDER HAS ANY ITEMS IN IT
	if [[ /Library/Application\ Support/JAMF/tmp/* == "" ]]; then
		echo -e "Recon Folder Empty, we love to see that!\n" >> $output
	else
		echo -e "The following files were found in the Recon directory:\n $reconleftovers" >> $output
		cp /Library/Application\ Support/JAMF/tmp/* $Recon_Directory_Copy
		#DIAGNOSTIC INFORMATION FOR RECON RESULTS. FOLLOWING THESE STEPS WILL HELP IDENTIFY PROBLEMATIC EXTENSION ATTRIBUTES AND/OR INVENTORY CHECK IN PROBLEMS
		echo -e "\nRecon leftovers found and listed above\nTo temporarily remediate, set Jamf_Recon_Resolver to TRUE or \n1.Open Terminal\n2.Type 'rm -r /Library/Application\ Support/JAMF/tmp/*'\nThis will remove all temporary files in the folder and allow the inventory update to complete.\nSometimes these files get stuck, so this helps reset them.\nIf they come back, examine the files copied to the directory you set for Recon_Directory_Copy. They should contain problematic scripts set as Extension Attributes" >> $output
	fi
else
	echo -e "Recon Recon Resolver set to invalid value\n" >> $output
fi


#Device_Signature_Error_Resolver
if [ "$DSER" = "TRUE" ] || [ "$DSER" = "CAUTIOUS" ];then
	if grep -Fq "A valid device signature is required to perform the action" $jamf_log
	then
		if [[ "$DSER" == TRUE ]];then
			echo -e "Your computer has a device signature error. In order to resolve it we'll need to run an API call. Checking if API credentials available..." >> $output
			if [[ "$APIUSER" != "" ]] && [[ "$APIPASS" != "" ]];then
				echo -e "Found API user credentials. Looking for Computer ID\n" >> $output
				echo -e "Running recon to get computer_id" >> $output
				computer_id=10
				if [[ "$computer_id" != "" ]];then
					echo -e "Computer ID: $computer_id\n Running /v1/jamf-management-framework/redeploy/{id}." >> $output
					#GET BEARER TOKEN FOR API CALL
					getBearerToken
					#REDEPLOY MANAGEMENT FRAMEWORK
					apiresponse=$(curl -X 'POST' \
						"$url/api/v1/jamf-management-framework/redeploy/$computer_id" \
						-H 'accept: application/json' \
						-H "Authorization: Bearer $bearerToken" \
						-d '')
					echo "$apiresponse" >> $output
					echo -e "Finished attempting to redeploy framework... invalidating token" >> $output
					invalidateToken
					if grep -Fq "deviceId" "$output"; then
						echo -e "Token invalidated...\nFramework successfully redeployed.\nRemoving Device Signature errors from jamf.log to avoid erroneous runs of DSER." >> $output
						sed -i '' '/Device Signature Error - A valid device signature is required to perform the action./d' $jamf_log
						echo -e "Jamf-Resolver removed lines with Device Signature error from Jamf.log, any new entries after this line will need to be addressed" >> $jamf_log
						echo -e "Jamf-Resolver removed lines with Device Signature error from Jamf.log, any new entries will need to be addressed" >> $output
					elif grep -Fq "httpStatus" "$output"; then
						echo -e "An error was encountered while trying to redeploy the framework. Your device still needs to run the API call" >> $output
					else
						echo -e "An error was encountered while trying to redeploy the framework. Your device still needs to run the API call" >> $output
					fi
				else
					echo -e "Unable to pull computer ID, please locate computer ID and run /v1/jamf-management-framework/redeploy/{id}" >> $output
				fi
			else
				echo -e "No API user credentials found. Please enter credentials for APIUSER and APIPASS to continue.\n" >> $output
			fi
		elif [[ "$DSER" == CAUTIOUS ]];then
			echo -e "Your computer has a device signature error. To resolve, please try using the /v1/jamf-management-framework/redeploy/{id} API." >> $output
		fi
	else
		echo -e "No device signature errors found in your jamf.log" >> $output
	fi
fi
