Tigase Messenger for macOS Interface
======================================

The menu interface for BeagleIM on the top will be showed as the following :

|images/chat01| 


Window
-------

click windows on the top and select contacts, the following windows will pop up. and then you can add add/edit/delete account and change your status here.

|images/contact01| 


Contacts
^^^^^^^^^^

Add a contact
~~~~~~~~~~~~~~

Click "+" sign at the left bottom from the last screen pop up. Then type in the JID of the user, do not use resources, just bare JID. You may enter a friendly nickname for the contact to be added to your friend list.In this tutorial *my friend* is selected as the name for the contact. When adding users, you have two options to select:

|images/contact02|


-  Allow presence subscription - This will allow sending of presence status and changes to this user on your roster. You may disable this to reduce network usage, however you will not be able to obtain status information.If you elect not to Allow presence subscription , you will not receive information if they are online, busy or away.

-  Request presence subscription - Turning this on will enable the applications to send presence changes to this person on the roster. You may disable this to reduce network usage, however they will not receive notifications if you turn off the phone

.. Note::

   These options are on by default and enable Tigase BeagleIM for iOS to behave like a traditional client.


If you do decide to Request presence subscription when adding a new contact, you will be presented with this screen when they add you back:

|images/contact03| 

By tapping yes, you will receive notifications of presence changes from your contact. This subscription will be maintained by the server, and will stay active with your friends list.

.. NOTE::
   You will only receive this option if 'Request presence subscription' is set to yes in account settings.

.. NOTE::
   If somebody not on your friends list adds you, you will receive this same message.

Edit/Delete a contact
^^^^^^^^^^^^^^^^^^^^^^^

When editing a contact, you may chose to change the account that has friended the user, edit a roster name (which will be shown on your roster). From submenual of windows, after clicking contacts, you can click "all" , following options will be showed:

|images/contact04| 

Here, you may also decide to selectively approve or deny subscription requests to and from the user. If you click authorize - "resend to"/"remove from"  , contacts on your roster will/ will not know whether you are online, busy, or away. 

If you decide to remove the contacts from your rost, click "remove" and then the contact will be removed from your roster.


User Status
^^^^^^^^^^^^

Your account status will be managed automatically by using the following rules by default

+-----------+--------------------------------------------------------------------------------------------------------------------------------+
| Status    | Behavior                                                                                                                       |
+-----------+--------------------------------------------------------------------------------------------------------------------------------+
| Online    | Application has focus on the device.                                                                                           |
+-----------+--------------------------------------------------------------------------------------------------------------------------------+
| Away / XA | Application is running in the background.                                                                                      |
+-----------+--------------------------------------------------------------------------------------------------------------------------------+
| Offline   | Application is killed or disconnected. If the device is turned off for a period of time, this will also set status to offline. |
+-----------+--------------------------------------------------------------------------------------------------------------------------------+

However, you may override this logic by tapping window - contacts , and selecting a status manually by using drop down list.

|images/status01|  |images/status02|


offline:
If offline is elected, it will be considered unavailable. And you will not receive message from your contacts.

Chats
^^^^^^

After adding contacts, go to window on the top and select Chats. Now you are able to open conversation window with your friends by click +sign.

|images/Chats01| 

Once you open the conversation window, you are able chat with your friend by typing. If you are tired of typing but you still want to chat, then just make a voice call or video call.

|images/Chats02| 


Preference
----------

Click BeagleIM on the top and select preference:
|images/preference| 

After that, the preference panel showed here could let you change some settings.


|images/preference02| 


General
^^^^^^^^^^

**Apperance**

-  | automatic, light and dark
   | adjust background brightness


**Chats list style**

-  | Minimal small large:
   | The lines of preview text(from less to more) to keep within the chat window without using internal or message archive. 

**Sent image quality**

-  | Low Medium High Higset Original:
   | The quailty of images will be sent out 

**Sent videos quality**

-  | Low Medium High Higset Original:
   | The quailty of videos will be sent out 

**Notifications**

This section has two options: 

-  | Show for messages from unknown senders:
   | Whether message will be showen if you receive a message from someone who is not in your contact list and does not have presence subscription 

-  | Show system manu icon:
   | Whether BeagleIM icon in the system menu bar be showed on the top of the screen

If "show sytem manu icon" is checked and you have ongoing/new conversation(even run in the background), the beagleIM icon will be in color showed on your top right of your screen.

|images/preference03| 


If "show sytem manu icon" is checked and you do not have ongoing/new conversation(not running in the background as well), the beagleIM icon will be in black and white showed on your top right of your screen.

|images/preference04| 



Accounts
^^^^^^^^^

**Add**
-  | Allows to add other XMPP account 

**Edit**

-  | Change password:
   | user password can be changed at here

-  | Connection details:
   | Nickname of user can be change at this window

-  | Public profile:
   | There is a blank space in the upper left corner where you may upload a photo as your avatar.

**Blocked**

-  | Lists of contacts which has been blocked


Advanced
^^^^^^^^^^^^^

-  | Automatic attachments download:
   | Sets the maximum size of files being sent to the user which may be automatically donwload. Default size is 10.0MB





.. |images/siskin03| image:: images/siskin03.png
.. |images/join01| image:: images/join01.png
.. |images/join02| image:: images/join02.png
.. |images/editcontacts01| image:: images/editcontacts01.png
.. |images/editcontacts02| image:: images/editcontacts02.png
.. |images/status| image:: images/status.png


