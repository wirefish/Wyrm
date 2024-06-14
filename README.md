# Wyrm

Wyrm is a framework for creating text-based multiplayer role-playing games, also
known as MUDs. It is designed to be played in a modern browser and includes an
integrated HTML5 client.

## Requirements

The Wyrm server is written in [Swift](https://swift.org). Follow the linked
instructions to install Swift on your platform.

## Getting Started

Type `make` to build everything. The output comprises:

- The server binary, located at `.build/debug/Wyrm`

- The client resources, located at `.build/client/`

To build a release server, use `swift build -c release`.

Before running the server for the first time, create a database used to store
player information. By default this file is expected to be located at
`/var/wyrm/wyrm.db`. Create it as follows:

    sqlite3 --init config/schema.sql /var/wyrm/wyrm.db

The server expects to be run from the root directory of the repository, i.e. the
directory that contains this README file. It serves resources from
`.build/client/` and loads the game world from `World/`.

To run the server, type `.build/debug/Wyrm`.
