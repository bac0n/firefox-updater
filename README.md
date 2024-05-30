### Firefox offline updater

Example of `/usr/lib/firefox/update-settings.ini`:
```ini
; If you modify this file updates may fail.
; Do not modify this file.

[Settings]
ACCEPTED_MAR_CHANNEL_IDS=firefox-mozilla-beta,firefox-mozilla-release
```

Example of `/etc/firefox/defaults/pref/channel-prefs.js`:
```js
/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
//

pref("app.update.channel", "beta");
```
