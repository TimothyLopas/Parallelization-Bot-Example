*** Settings ***
Documentation       Template robot main suite.

Library             RPA.Browser.Playwright    timeout=30s    auto_closing_level=SUITE
...                 run_on_failure=Take Screenshot \ EMBED
Library             RPA.Robocorp.Vault
Library             RPA.Cloud.AWS
Library             RPA.Salesforce
Library             TeamsMessages.py
Library             RPA.Excel.Files
Library             RPA.Tables
Library             String
Library             RPA.Robocorp.WorkItems


*** Tasks ***
Collect cases and append property tax details
    Authenticate to S3
    Authenticate to Salesforce
    For Each Input Work Item    Collect property tax details, append to Salesforce case and send Teams message


*** Keywords ***
Authenticate to S3
    ${secret}=    Get Secret    aws
    Init S3 Client
    ...    ${secret}[AWS_KEY_ID]
    ...    ${secret}[AWS_KEY]
    ...    ${secret}[AWS_REGION]

Authenticate to Salesforce
    ${sf_secret}=    Get Secret    salesforce
    Auth With Token    ${sf_secret}[api_username]    ${sf_secret}[api_password]    ${sf_secret}[api_token]

Open Google Maps webpage
    New Browser    headless=${FALSE}
    New context
    New Page    https://www.google.com/maps

Collect property tax details, append to Salesforce case and send Teams message
    Open Google Maps webpage
    # ${case_payload}=    Get Work Item Payload
    ${case}=    Get Work Item Variable    case_number
    ${secret}=    Get Secret    salesforce
    ${base_url}=    Set Variable    ${secret}[base_url]
    ${valid_case}=    Set Variable    ${FALSE}
    ${success}=    Set Variable    ${FALSE}
    ${case}=    Convert To String    ${case}
    ${case_length}=    Get Length    ${case}
    IF    ${case_length} < ${8}
        ${case}=    Format string    {0:08d}    ${case}
        ${valid_case}=    Set Variable    ${TRUE}
    END

    # You could structure this with TRY...EXCEPT...ELSE...FINALLY whereby
    # you don't check for validity, you just try to submit to sfdc first off
    # and then you catch the SFDC error and then release input work items
    # with your exception message.
    IF    ${valid_case}
        ${address}    ${case_id}=    Find mailing address from case number    ${case}
        ${valid}=    Validate Address Structure    ${address}
        IF    ${valid}
            Search for property    ${address}
            Append property image to case notes    ${address}    ${case_id}
            ${teams_message}=    Catenate
            ...    Case ${case} has been updated on SalesForce:
            ...    https://${base_url}.lightning.force.com/lightning/r/Case/${case_id}/view
            Run Keyword And Warn On Failure    Send Message To Sfdc Messages Channel    ${teams_message}

            Release Input Work Item
            ...    DONE
            # This path would be in the "ELSE" block
        ELSE
            Release Input Work Item
            ...    FAILED
            ...    exception_type=BUSINESS
            ...    code=INVALID_ADDRESS_STRUCTURE
            ...    message=The address (${address}) is invalid. Correct in Salesforce first, then rerun.
            # This path would be in an "EXCEPT" block. If you caught the exception into a variable
            # by writing your EXCEPT block like:
            #
            # EXCEPT    exception message    AS    ${e}
            #
            # You could pass ${e} as the message to control room.. but then you have to figure out
            # what exception messages SFDC returns and catch it because the EXCEPT matches on
            # string only (you can use glob patterns to make it easier to catch).
        END
    ELSE
        Release Input Work Item
        ...    FAILED
        ...    exception_type=APPLICATION
        ...    code=CASE_LENGTH_ERROR
        ...    message=Case length is not valid and cannot be passed into Salesforce.
        # This path would be in an "EXCEPT" block
    END

    # This would be in the "FINALLY" block.
    Close Browser

Find mailing address from case number
    [Arguments]    ${case_number}
    ${case_query}=
    ...    Salesforce Query Result As Table
    ...    SELECT Id, ContactId FROM Case WHERE CaseNumber = '${case_number}'
    ${case_id}=    Set Variable    ${case_query}[0][0]
    ${contact_id}=    Set Variable    ${case_query}[0][1]
    ${contact_query}=
    ...    Salesforce Query Result As Table
    ...    SELECT Id, MailingAddress FROM Contact WHERE Id = '${contact_id}'
    ${mailing_address_dict}=    Set Variable    ${contact_query}[0][1]
    ${mailing_address}=    Catenate
    ...    ${mailing_address_dict}[street]
    ...    ${mailing_address_dict}[city], ${mailing_address_dict}[state]
    ...    ${mailing_address_dict}[postalCode]
    RETURN    ${mailing_address}    ${case_id}

Validate Address Structure
    [Arguments]    ${address}

    TRY
        Should match regexp    ${address}    ^\\d+[^?/\\\\!@]+\\d+$
    EXCEPT
        RETURN    ${FALSE}
    ELSE
        RETURN    ${TRUE}
    END

Search for property
    [Arguments]    ${address}
    ${address_upper}=    Convert To Upper Case    ${address}
    ${address_filename}=    Replace String    ${address_upper}    ${SPACE}    _
    Fill Text    id=searchboxinput    ${address_upper}
    Keyboard Key    press    Enter
    Sleep    5    # would be nice to replace this with a `wait for an elements state`
    Take Screenshot    ${OUTPUT_DIR}${/}${address_filename}    fileType=jpeg    quality=10    fullPage=False

Append property image to case notes
    [Arguments]    ${address}    ${case_id}
    ${address_upper}=    Convert To Upper Case    ${address}
    ${address_filename}=    Replace String    ${address_upper}    ${SPACE}    _
    ${caseFeed_data}=
    ...    Create Dictionary
    ...    ParentId=${case_id}
    ...    Body=${address}
    ...    Title=${address}
    ${caseFeed}=    Create Salesforce Object    FeedItem    ${caseFeed_data}
    ${binary_file_data}=    Evaluate    open("output/${address_filename}.jpeg", 'rb').read()
    ${base64_encoded_data}=    Evaluate    base64.encodebytes($binary_file_data).decode('utf-8')
    ${contentVersion_data}=
    ...    Create Dictionary
    ...    VersionData=${base64_encoded_data}
    ...    PathOnClient=${OUTPUT_DIR}${/}${address_filename}.jpeg
    ...    FirstPublishLocationId=0058c000009XrFN
    ...    Origin=H
    ...    ContentLocation=S
    ${contentVersion}=    Create Salesforce Object    ContentVersion    ${contentVersion_data}
    ${caseAttachment_data}=
    ...    Create Dictionary
    ...    Type=Content
    ...    FeedEntityID=${caseFeed}[id]
    ...    RecordId=${contentVersion}[id]
    Create Salesforce Object    FeedAttachment    ${caseAttachment_data}
    Log    Case Notes Updated    console=${TRUE}
