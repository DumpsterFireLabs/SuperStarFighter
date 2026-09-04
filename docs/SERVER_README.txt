Super Star Fighter - Dedicated Server (Windows x64, Beta 10)

Unzip all files into a directory. Start from PowerShell:

  $env:SSF_LOBBY_PASSWORD = 'choose-a-private-lobby-password'
  .\SuperStarFighter-Server.exe -- --port=7777 --max-players=32

The package starts in server mode without graphics or audio. No Godot editor,
source checkout, client assets or separate PCK file is required. Use the same
game/protocol version on clients (compatibility 30, binary packets 12).

Set the lobby password before starting. The example is not a public password.
Use the --port value when connecting directly. Configure any network/firewall
access appropriate to your host; this package does not change those settings.
Console/server logs report startup, joins and match activity. Stop with Ctrl+C.

The executable uses the official Godot template with server-only game resources.
It is not a custom engine binary with renderer code compiled out. This build is
unsigned. Native distribution and representative-hardware release acceptance
are tracked separately.

See THIRD_PARTY_NOTICES.txt and GODOT_COPYRIGHT.txt for engine/component notices.
