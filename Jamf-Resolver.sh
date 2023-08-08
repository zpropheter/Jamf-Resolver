#!/bin/bash

#Jamf-Resolver is designed to walk admins and end-users through resolutions to common issues. It starts with some of the most common issues and progresses into some of the more complex items from there



#User defined Variables- set to 'TRUE' , 'FALSE' , or 'CAUTIOUS' to enable or disable each feature. 'CAUTIOUS' variable does read only and requires user intervention to remove files
JRR=FALSE
DSER=FALSE
MCR=FALSE
APIUSER="API_Username"
APIPASS="API_password"
url="https://serverurl.jamfcloud.com"


#HARD CODED VARIABLES
loggedInUser=$( echo "show State:/Users/ConsoleUser" | /usr/sbin/scutil | /usr/bin/awk '/Name :/ && ! /loginwindow/ { print $3 }' )
reconleftovers=$(ls /Library/Application\ Support/JAMF/tmp/)
Recon_Directory_Copy=/Users/Shared/
jamf_log=/private/var/log/jamf.log
currenttime=$(date +"%D %T")


#DEFINE WHERE YOU WANT RESULTS SAVED
output=/Users/Shared/output.txt
#CREATE NEW LOG FILE
echo "New output file generated on $currenttime" > $output

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


#Device_Signature_Error_Resolver
if [ "$DSER" = TRUE ] || [ "$DSER" = CAUTIOUS ];then
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
					echo -e "Unable to pull computer ID, please locate computer ID and run /v1/jamf-management-framework/redeploy/{id}\n" >> $output
				fi
			else
				echo -e "No API user credentials found. Please enter credentials for APIUSER and APIPASS to continue.\n" >> $output
			fi
		else [[ "$DSER" == CAUTIOUS ]]
			echo -e "Your computer has a device signature error. To resolve, please try using the /v1/jamf-management-framework/redeploy/{id} API.\n" >> $output
			fi
	else
		echo -e "No device signature errors found in your jamf.log\n" >> $output
	fi
elif [[ "$DSER" == FALSE ]];then
	echo -e "Device Signature Error Resolver is not turned on\n" >> $output
else 
	echo -e "Incorrect Variable set for Device Signature Error Resolver\n" >> $output
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
