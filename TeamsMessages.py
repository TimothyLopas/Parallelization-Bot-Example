"""A custom Python library that allows us to sent a message to a Teams channel
using webhooks. This library leverages another library, pymsteams, that is open source."""

import pymsteams
from robot.api import logger
from RPA.Robocorp.Vault import Vault

class TeamsMessages:
    """The library is used to send messages to teams channels using webhook URIs

    Something to note when using Robot Framework: when creating a Python keyword library, 
    the module name must correspond to the class name (in CamelCase). This goes against PEP8 
    but is a Robot Framework convention."""

    def send_message_to_sfdc_messages_channel(self, message: str) -> None:
        """Sends a message to the SFDC Messages channel on MS Teams

        :param message: the text message you want to sent teams
        :return: None
        """
        _secret = Vault().get_secret("teams")
        uri = _secret["uri"]
        my_teams_message = pymsteams.connectorcard(uri)
        my_teams_message.text(message)
        logger.info(f"Message sent to SFDC Messages on Teams: {message}")
        my_teams_message.send()