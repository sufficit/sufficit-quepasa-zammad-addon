# zammad-addon-quepasa

Adds WhatsApp as a channel to [Zammad](https://zammad.org) via
[Quepasa](https://gitlab.com/digiresilience/link/quepasa)

You need [Quepasa](https://gitlab.com/digiresilience/link/quepasa)
installed and working to use this addon.

## Development

1. Edit the files in `src/`

   Migration files should go in `src/db/addon/quepasa` ([see this post](https://community.zammad.org/t/automating-creation-of-custom-object-attributes/3831/2?u=abelxluck))

2. Update version and changelog in `quepasa-skeleton.szpm`
3. Build a new package `make`

   This outputs `dist/quepasa-vXXX.szpm`

4. Install the szpm using the zammad package manager.

5. Repeat

### Create a new migration

Included is a helper script to create new migrations. You must have the python
`inflection` library installed.

- debian/ubuntu: `apt install python3-inflection`
- pip: `pip install --user inflection`
- or create your own venv

To make a new migration simply run:

```
make new-migration
```

## Help and Support

Join us in our public matrix channel [#cdr-link-dev-support:matrix.org](https://matrix.to/#/#cdr-link-dev-support:matrix.org?via=matrix.org&via=neo.keanu.im).

## License

[![License GNU AGPL v3.0](https://img.shields.io/badge/License-AGPL%203.0-lightgrey.svg)](https://gitlab.com/digiresilience/link/zamamd-addon-quepasa/blob/master/LICENSE.md)

This is a free software project licensed under the GNU Affero General
Public License v3.0 (GNU AGPLv3) by [The Center for Digital
Resilience](https://digiresilience.org) and [Guardian
Project](https://guardianproject.info).

🤠

### SUFFICIT #########################

## Important to add WHATSAPP specific fields
zammad run rake db:migrate

zammad run rake assets:precompile
systemctl restart zammad