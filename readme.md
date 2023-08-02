# Simple shell UI using whiptail to migrate volumes in kubernetes clusters to a new storage class

Needs
 - kubectl with pv-migrate installed
 - yq
 - whiptail


This was created to help me migrate data with minimal impact after changing the storage class in our clusters.
This might not do what you need, but it might be a starting point.
It wont win any beauty contests...

