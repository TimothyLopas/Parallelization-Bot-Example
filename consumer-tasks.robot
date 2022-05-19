*** Settings ***
Documentation       Template robot main suite.

Library             RPA.Browser.Playwright    timeout=00:00:30    auto_closing_level=SUITE    run_on_failure=Take Screenshot \ EMBED
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
    New Page    https://www.google.com/maps

Collect property tax details, append to Salesforce case and send Teams message
    Open Google Maps webpage
    # ${case_payload}=    Get Work Item Payload
    ${case}=    Get Work Item Variable    CaseNumber
    ${secret}=    Get Secret    salesforce
    ${base_url}=    Set Variable    ${secret}[base_url]
    ${valid_case}=    Set Variable    ${FALSE}
    ${success}=    Set Variable    ${FALSE}
    ${case}=    Convert To String    ${case}
    ${case_length}=    Get Length    ${case}
    IF    ${case_length} < ${8}
        IF    ${case_length} == ${1}
            ${case}=    Set Variable    0000000${case}
            ${valid_case}=    Set Variable    ${TRUE}
        ELSE IF    ${case_length} == ${2}
            ${case}=    Set Variable    000000${case}
            ${valid_case}=    Set Variable    ${TRUE}
        ELSE IF    ${case_length} == ${3}
            ${case}=    Set Variable    00000${case}
            ${valid_case}=    Set Variable    ${TRUE}
        ELSE IF    ${case_length} == ${4}
            ${case}=    Set Variable    0000${case}
            ${valid_case}=    Set Variable    ${TRUE}
        ELSE IF    ${case_length} == ${5}
            ${case}=    Set Variable    000${case}
            ${valid_case}=    Set Variable    ${TRUE}
        ELSE IF    ${case_length} == ${6}
            ${case}=    Set Variable    00${case}
            ${valid_case}=    Set Variable    ${TRUE}
        ELSE IF    ${case_length} == ${7}
            ${case}=    Set Variable    0${case}
            ${valid_case}=    Set Variable    ${TRUE}
        END
    END

    IF    ${valid_case}
        ${address}    ${case_id}=    Find mailing address from case number    ${case}
        ${valid}=    Validate Address Structure    ${address}
        IF    ${valid}
            Search For propery    ${address}
            Append property image to case notes    ${address}    ${case_id}
            ${teams_message}=    Set Variable
            ...    Case ${case} has been updated on SalesForce: https://${base_url}.lightning.force.com/lightning/r/Case/${case_id}/view
            Run Keyword And Warn On Failure    Send Message To Sfdc Messages Channel    ${teams_message}

            Release Input Work Item
            ...    DONE
        ELSE
            Release Input Work Item
            ...    FAILED
            ...    exception_type=BUSINESS
            ...    code=INVALID_ADDRESS_STRUCTURE
            ...    message=The address (${address}) is invalid. Correct in Salesforce first, then rerun.
        END
    ELSE
        Release Input Work Item
        ...    FAILED
        ...    exception_type=APPLICATION
        ...    code=CASE_LENGTH_ERROR
        ...    message=Case length is not valid and cannot be passed into Salesforce.
    END

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
    ${mailing_address}=    Set Variable
    ...    ${mailing_address_dict}[street]${SPACE}${mailing_address_dict}[city],${SPACE}${mailing_address_dict}[state]${SPACE}${mailing_address_dict}[postalCode]
    RETURN    ${mailing_address}    ${case_id}

Validate Address Structure
    [Arguments]    ${address}
    ${valid}=    Set Variable    ${TRUE}
    ${address_characters}=    Split String To Characters    ${address}

    ${first_char}=    Set Variable    ${address_characters}[0]
    ${last_char}=    Set Variable    ${address_characters}[-1]

    ${first_char_alpha}=    Evaluate    $first_char.isalpha()
    ${last_char_alpha}=    Evaluate    $first_char.isalpha()

    IF    ${first_char_alpha}
        ${valid}=    Set Variable    ${FALSE}
    END
    IF    ${last_char_alpha}
        ${valid}=    Set Variable    ${FALSE}
    END

    FOR    ${char}    IN    @{address_characters}
        IF    "${char}" == "?"
            ${valid}=    Set Variable    ${FALSE}
        ELSE IF    "${char}" == "/"
            ${valid}=    Set Variable    ${FALSE}
        ELSE IF    "${char}" == "\"
            ${valid}=    Set Variable    ${FALSE}
        ELSE IF    "${char}" == "!"
            ${valid}=    Set Variable    ${FALSE}
        ELSE IF    "${char}" == "@"
            ${valid}=    Set Variable    ${FALSE}
        END
    END

    RETURN    ${valid}

Search for propery
    [Arguments]    ${address}
    ${address_upper}=    Convert To Upper Case    ${address}
    ${address_filename}=    Replace String    ${address_upper}    ${SPACE}    _
    Fill Text    id=searchboxinput    ${address_upper}
    Keyboard Key    press    Enter
    Sleep    5
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
    Log    Case Notes Updated
