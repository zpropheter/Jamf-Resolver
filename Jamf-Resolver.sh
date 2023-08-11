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
APIUSER="API_USERNAME"
APIPASS="API_PASSWORD"
url="https://yourserver.jamfcloud.com"
JRR=FALSE
DSER=TRUE
MCR=FALSE

#HARD CODED VARIABLES
loggedInUser=$( echo "show State:/Users/ConsoleUser" | /usr/sbin/scutil | /usr/bin/awk '/Name :/ && ! /loginwindow/ { print $3 }' )
reconleftovers=$(ls /Library/Application\ Support/JAMF/tmp/)
Recon_Directory_Copy=/Users/Shared/
jamf_log=/private/var/log/jamf.log
currenttime=$(date +"%D %T")
serialnumber=$( system_profiler SPHardwareDataType | grep Serial |  awk '{print $NF}' )
output=/Users/Shared/output.txt


#CREATE NEW LOG FILE
echo "New output file generated on $currenttime" > $output

#CHECK IF API CREDENTIALS AVAILABLE
APISTATUS=$(if [[ $APIUSER != "" ]] && [[ $APIPASS != "" ]];then
echo "ENABLED"
else
echo "DISABLED"
fi)

#CHECK FOR CUSTOM PLIST ALREADY INSTALLED ON THE COMPUTER
	redeployresponse=$(defaults read /Library/Managed\ Preferences/com.propheter.jresolver "Computer ID")

#HARD CODED VARIABLE FOR API BEARER TOKEN RETRIEVAL
getBearerToken() {
	response=$(curl -s -u "$APIUSER":"$APIPASS" "$url"/api/v1/auth/token -X POST)
	bearerToken=$(echo "$response" | plutil -extract token raw -)
	tokenExpiration=$(echo "$response" | plutil -extract expires raw - | awk -F . '{print $1}')
	tokenExpirationEpoch=$(date -j -f "%Y-%m-%dT%T" "$tokenExpiration" +"%s")
}

#create a REDEPLOY COMMAND
reDeployFramework() {
	#REDEPLOY MANAGEMENT FRAMEWORK
	apiresponse=$(curl -X 'POST' \
						"$url/api/v1/jamf-management-framework/redeploy/$computer_id" \
						-H 'accept: application/json' \
						-H "Authorization: Bearer $bearerToken" \
						-d '')
	echo "$apiresponse" >> $output
	echo -e "Finished attempting to redeploy framework... invalidating token" >> $output
}

#API CALL TO GET DEVICE ID FROM RECORD
getDeviceRecord() {
	devicerecord=$(curl -X 'GET' \
	"$url/api/v1/computers-inventory?section=GENERAL&page=0&page-size=100&sort=general.name%3Aasc&filter=hardware.serialNumber%3D%3D%22$serialnumber%22" \
	-H 'accept: application/json' \
	-H "Authorization: Bearer $bearerToken")
	deviceid=$(/usr/bin/plutil -extract "results".0."id" raw -o - - <<< "$devicerecord")
	echo "Device ID: $deviceid" >> $output
}

#TOKEN INVALIDATION ARRAY
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

#CLEANUP ARRAY
cleanOutTheLogs() {
	echo -e "Token invalidated...\nFramework successfully redeployed.\nRemoving Device Signature errors from jamf.log to avoid erroneous runs of DSER." >> $output
	sed -i '' '/Device Signature Error - A valid device signature is required to perform the action./d' $jamf_log
	echo -e "Jamf-Resolver removed lines with Device Signature error from Jamf.log, any new entries after this line will need to be addressed" >> $jamf_log
	echo -e "Jamf-Resolver removed lines with Device Signature error from Jamf.log, any new entries will need to be addressed" >> $output
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
	echo -e "Recon Resolver turned off\n" >> $output
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
	echo -e "Recon Resolver set to invalid value\n" >> $output
fi

#MDM_Communication_Resolver
#CHECK IF ENABLED
if [ "$MCR" = "TRUE" ] || [ "$MCR" = "CAUTIOUS" ];then
	result=$(log show --style compact --predicate '(process CONTAINS "mdmclient")' --last 1d | grep "Unable to create MDM identity")
	if [[ $result == '' ]]; then
		echo -e "MDM is communicating, no action necessary.\n"
	elif [[ "$result" != '' ]] && [[ "$MCR" == "TRUE" ]];then
		echo "MDM is broken.\n"
		profiles validate -type enrollment
		profiles renew -type enrollment
		if [[ $result == '' ]]; then
			echo -e "MDM is communicating after renewing enrollment, no further action necessary.\n"
		else
			echo -e "MDM is still broken. Your device will need to be wiped and re-enrolled if it has a DEP non-removable profile.\n"
		fi
	else [[ "$result" != '' ]] && [[ "$MCR" == "CAUTIOUS" ]]
		echo -e "MDM is broken.\nThe recommended workflow for this issue is to do the following.\n1.Open Terminal\n2.Type: sudo profiles validate -type enrollment\n3.Press Enter\n4.Type: sudo profiles renew -type enrollment\n5.Press Enter\nIf the command processes correctly the issue should resolve. If it errors out, the device may have non-removable profiles installed from DEP and need to be wiped and re-enrolled."
	fi
elif [[ $MCR == "FALSE" ]]; then
	echo -e "MDM Communication Resolver is not turned on\n" >> $output
else
	echo -e "Incorrect Variable set for MDM Communication Resolver\n" >> $output
fi

#Device_Signature_Error_Resolver
if [ "$DSER" = TRUE ];then
	if grep -Fq "A valid device signature is required to perform the action" $jamf_log
	then
		if [[ -n $redeployresponse ]] || [ "$APISTATUS" == ENABLED ];then
			if [[ $redeployresponse != "" ]];then
				computer_id=$redeployresponse
				echo -e "Redeploying framework from plist\n-Getting Bearer Token\n"
				getBearerToken
				echo -e "Got Bearer Token... redeploying framework\n-Computer ID:$computer_id selected for redeploying framework\n"
				reDeployFramework
				echo -e "-Framework redeployed, cleaning out logs\n"
				invalidateToken
				cleanOutTheLogs
				echo -e "-Logs cleaned out, exiting to next resolver function\n"
			else
				echo -e "Running API to redeploy framework\n-Getting Bearer Token\n"
				getBearerToken 
				echo -e "-Got Bearer Token... getting Device Record\n"
				getDeviceRecord
				echo -e "-Checking Device Record\n"
				computer_id=$deviceid
				if grep -Fq "Could not extract value" $output
				then 
					echo -e "**Unable to get Computer ID from API**\n"
				else
					echo -e "-Computer ID:$computer_id selected for redeploying framework\n"
					reDeployFramework
					echo -e "-Framework redeployed, cleaning out logs\n"
					invalidateToken
					cleanOutTheLogs
					echo -e "-Logs cleaned out, exiting to next resolver function\n"
				fi
			fi
		else
			echo -e "Unable to get Device ID"
		fi
		
	else
		echo -e "No Device Signature Error detected\n" >> $output
	fi
elif [ "$DSER" = FALSE ]; then
	echo -e "Device Signature Error Resolver turned off" > $output
elif [ "$DSER" = CAUTIOUS ];then
		if grep -Fq "A valid device signature is required to perform the action" $jamf_log; then
			echo -e "A Device signature error has been found, you will need to redeploy the management framework in order to resolve communication with your Jamf server.\n"
		fi
	echo -e "Invalid Variable for Device Signature Error Resolver" >> $output
fi
