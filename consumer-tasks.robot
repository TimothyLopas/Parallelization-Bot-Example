*** Settings ***
Documentation       This is the consumer portion of the bot. This bot will take each Work Item created in the producer portion of the bot
...                 and extract the case number from it. That case number will be looked up in Salesforce and the associated contact's mailing address
...                 will be extracted. The address will go through light validation and then be sent to Google Maps. The Google Maps screenshot will
...                 then be attached to the Salesforce Case and a Teams message will be sent informing a channel of the Case updates.

Library             RPA.Browser.Playwright    timeout=30s    auto_closing_level=SUITE
...                     run_on_failure=Take Screenshot \ EMBED
Library             RPA.Robocorp.Vault
Library             RPA.Cloud.AWS    robocloud_vault_name=aws
Library             RPA.Salesforce
Library             TeamsMessages.py
Library             RPA.Excel.Files
Library             RPA.Tables
Library             String
Library             RPA.Robocorp.WorkItems


*** Tasks ***
Collect cases and append property tax details
    Init s3 client    use_robocloud_vault=${TRUE}
    Authenticate to Salesforce
    For Each Input Work Item
    ...    Collect property tax details, append to Salesforce case and send Teams message


*** Keywords ***
Authenticate to Salesforce
    ${sf_secret}=    Get Secret    salesforce
    Auth With Token    ${sf_secret}[api_username]    ${sf_secret}[api_password]    ${sf_secret}[api_token]

Open Google Maps webpage
    New Browser    headless=${FALSE}
    New Context
    New Page    https://www.google.com/maps

Accept Cookies
    ${element}=    Get Element    xpath=//button[@aria-label="Reject all"][text()="Reject allAccept all"]
    Log    ${element}
    Click    ${element}

Collect property tax details, append to Salesforce case and send Teams message
    Open Google Maps webpage
    Run Keyword And Continue On Failure    Accept Cookies
    ${case}=    Get Work Item Variable    case_number
    ${secret}=    Get Secret    salesforce
    ${base_url}=    Set Variable    ${secret}[base_url]
    ${valid_case}=    Set Variable    ${FALSE}
    ${success}=    Set Variable    ${FALSE}
    ${case}=    Convert To String    ${case}
    ${case_length}=    Get Length    ${case}
    IF    ${case_length} < ${8}
        ${case_as_int}=    Convert To Integer    ${case}
        ${case}=    Format string    {0:08d}    ${case_as_int}
    END

    TRY
        ${address}    ${case_id}=    Find mailing address from case number    ${case}
    EXCEPT
        Release Input Work Item
        ...    FAILED
        ...    exception_type=APPLICATION
        ...    code=CASE_LENGTH_ERROR
        ...    message=Case length is not valid and cannot be passed into Salesforce.
        RETURN
    END

    TRY
        Should match regexp    ${address}    ^\\d+[^?/\\\\!@\\*\=]+\\d+$
    EXCEPT
        Release Input Work Item
        ...    FAILED
        ...    exception_type=BUSINESS
        ...    code=INVALID_ADDRESS_STRUCTURE
        ...    message=The address (${address}) is invalid. Correct in Salesforce first, then rerun.
        RETURN
    END
    TRY
        Search for property    ${address}
    EXCEPT
        Release Input Work Item
        ...    FAILED
        ...    exception_type=BUSINESS
        ...    code=INVALID_ADDRESS
        ...    message=The address (${address}) is invalid. Please contact the customer to confirm and update in Salesforce.
        RETURN
    END

    TRY
        Append property image to case notes    ${address}    ${case_id}
    EXCEPT
        Release Input Work Item
        ...    FAILED
        ...    exception_type=APPLICATION
        ...    code=INVALID_ADDRESS
        ...    message=Salesforce failed to attach the image to the case.
        RETURN
    END

    TRY
        ${teams_message}=    Catenate
        ...    Case ${case} has been updated on SalesForce:
        ...    https://${base_url}.lightning.force.com/lightning/r/Case/${case_id}/view
        Send Message To Sfdc Messages Channel    ${teams_message}
    EXCEPT
        Release Input Work Item
        ...    FAILED
        ...    exception_type=APPLICATION
        ...    code=TEAMS_SEND_ERROR
        ...    message=Teams failed to receive the messgae properly
    ELSE
        Release Input Work Item
        ...    DONE
    END
    [Teardown]    Close Browser

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

Search for property
    [Arguments]    ${address}
    ${address_upper}=    Convert To Upper Case    ${address}
    ${address_filename}=    Replace String    ${address_upper}    ${SPACE}    _
    Wait Until Network Is Idle    timeout=10s
    Fill Text    id=searchboxinput    ${address_upper}
    Keyboard Key    press    Enter
    Wait For Elements State    xpath=//button[@class="S9kvJb"][@data-value="Directions"]
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
