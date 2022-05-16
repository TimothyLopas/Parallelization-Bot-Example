*** Settings ***
Documentation       Template robot main suite.

Library             RPA.Robocorp.Vault
Library             RPA.Salesforce


*** Tasks ***
Clear Salesforce
    Authenticate to Salesforce
    Delete all case comments


*** Keywords ***
Authenticate to Salesforce
    ${sf_secret}=    Get Secret    salesforce
    Auth With Token    ${sf_secret}[api_username]    ${sf_secret}[api_password]    ${sf_secret}[api_token]

 Delete all case comments
    ${casecomment_query}=
    ...    Salesforce Query Result As Table
    ...    SELECT Id FROM FeedAttachment
    ${len}=    Get Length    ${casecomment_query}
    Log To Console    Number of FeedAttachments is: ${len}
    FOR    ${row}    IN    @{casecomment_query}
        Log To Console    Deleting FeedAttachmentId: ${row}[Id]
        ${attachment_id}=    Set Variable    ${row}[Id]
        Delete Salesforce Object    FeedAttachment    ${attachment_id}
    END

    ${casecomment_query}=
    ...    Salesforce Query Result As Table
    ...    SELECT Id FROM FeedItem
    ${len}=    Get Length    ${casecomment_query}
    Log To Console    Number of FeedItems is: ${len}
    FOR    ${row}    IN    @{casecomment_query}
        Log To Console    Deleting FeedItemtId: ${row}[Id]
        ${feed_entity_id}=    Set Variable    ${row}[Id]
        Delete Salesforce Object    FeedItem    ${feed_entity_id}
    END

    ${casecomment_query}=
    ...    Salesforce Query Result As Table
    ...    SELECT Id FROM ContentDocument WHERE FileType='jpeg'
    ${len}=    Get Length    ${casecomment_query}
    Log To Console    Number of ContentDocuments is: ${len}
    FOR    ${row}    IN    @{casecomment_query}
        Log To Console    Deleting ContentDocumentId: ${row}[Id]
        ${record_id}=    Set Variable    ${row}[Id]
        Delete Salesforce Object    ContentDocument    ${record_id}
    END
