*** Settings ***
Documentation       This is the producer portion of the bot. This bot will download a file from an AWS S3 bucket and
...                 then extract the 500+ caese numbers from it. Each case number and other relevant data will be packaged
...                 up into a Work Item variable and the Work Item will be created and saved.
...                 This Work Item will be recalled and used as an input in the next step; the consumer portion of the bot.

Library             RPA.Browser.Playwright    timeout=00:00:30    auto_closing_level=SUITE    run_on_failure=Take Screenshot \ EMBED
Library             RPA.Robocorp.Vault
Library             RPA.Cloud.AWS
Library             RPA.Salesforce
Library             TeamsMessages.py
Library             RPA.Excel.Files
Library             RPA.Tables
Library             String
Library             RPA.Robocorp.WorkItems


*** Variables ***
${CASE_FILE_NAME}=          Producer-Consumer_Cases.xlsx
${AWS_DOWNLOAD_BUCKET}=     robocorp-test


*** Tasks ***
Collect cases and append property tax details
    Authenticate to S3
    Authenticate to Salesforce
    Download file from S3 bucket    ${AWS_DOWNLOAD_BUCKET}    Producer-Consumer${/}${CASE_FILE_NAME}
    ${cases}=    Open Excel file and extract cases
    Create Case Work Items    ${cases}


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

Download file from S3 bucket
    [Arguments]    ${bucket_name}    ${file_name}
    @{file_list}=    Create List    ${file_name}
    Download Files    ${bucket_name}    ${file_list}    ${OUTPUT_DIR}
    Log    AWS S3 file download complete

Open excel file and extract cases
    Open Workbook    ${OUTPUT_DIR}${/}${CASE_FILE_NAME}
    ${cases_table}=    Read Worksheet As Table    Sheet1    header=${TRUE}
    ${cases_column}=    Get Table Column    ${cases_table}    Cases
    RETURN    ${cases_column}

Create Case Work Items
    [Arguments]    ${cases}
    FOR    ${case}    IN    @{cases}
        &{case_variables}=    Create Dictionary    CaseNumber=${case}
        Create Output Work Item    variables=${case_variables}    save=${TRUE}
    END
