# pocus

pocus is a simple server provisioning solution relying on standard UNIX tools.

**WARNING**: pocus is still in its early phases which means it can contain bugs,
lack documentation, or flexibility. It's currently being developed against an
OpenBSD target and hence may not work on other operating systems.
**Contributions to make it work on Linux and BSDs are welcome!**

## Motivation

I was working on [www.whoishiring.jobs](https://www.whoishiring.jobs) and wanted
to set up an OpenBSD virtual machine for it. I found the existing tools to be
unsuitable due to the following reasons:

1. YAML-based "programming".
2. Having to translate simple UNIX commands (e.g. `cp from to`) into
  tool-specific syntax.
3. Requiring an agent on the server.
4. Requiring Python, which, while prevalent, isn't a standard UNIX tool.
5. Unreadable output.

pocus was created to address all those needs and was successfully used to
provision the aforementioned OpenBSD machine.

## Installation

pocus has minimal dependencies. The client and server need a POSIX shell, rsync,
and SSH. If these are installed then clone pocus via:

```
git clone https://github.com/gregnavis/pocus.git
```

After changing to the `pocus` directory (or adding `pocus/bin` to `PATH`),
you're now ready to provision your first server! Before doing so, it's essential
to understand the core concepts used in pocus.

## Concepts

There are five essential concepts in pocus.

### Concept 1: Spell

A spell is a regular shell script responsible for setting up a specific aspect
of the server. For example, setting up a work server may require one spell to
set up SSH and another spell for nginx. Spells exist only to organize more
complex setups. There's nothing preventing you from setting everything up from a
single spell.

### Concept 2: Spellbook

A spellbook is comprised of:

1. A sequence of spells executed in alphabetical order.
2. Additional files used by spells.

The convention is to prefix spell names with digits to achieve the desired
order. To continue the example from the previous section, if the spellbook has
to set up SSH before nginx then the respective spells can be named `1_ssh`
and `2_nginx`.

A spell may need access to additional files. For example, the SSH spell may need
`sshd_config` to copy to the target. Those files are also part of the spellbook,
as some spells may not function without them.

The exit status of a spell determines the next step in the execution of
the spellbook:

| Status | Description                                                   |
| -----: | :------------------------------------------------------------ |
|      0 | The spell succeeded, proceed to the next spell                |
|      1 | The spell failed, terminate execution                         |
|      2 | The spell was skipped, proceed to the next spell              |
|    127 | There was a problem with pocus internals, terminate execution |

### Concept 3: Target

A target is the description of the server where the spellbook will be run. The
target description must include the server to connect to. It can also specify
connection options. An example target definition:

```
target_host=johnsmith@openbsd.example.com
target_rsync_options=--rsync-path=openrsync
```

### Concept 4: Commands

Commands are helper shell functions that ship with pocus that are more suitable
for server provisioning than standard UNIX commands. Their use is entirely
**optional** (spells are regular scripts, after all), but highly recommended.

For example, the aforementioned `sshd_config` could be installed via `cp`, but
this would lead to a few problems:

1. The command would be long and repetitive: `cp $POCUS_SPELLBOOK_FILES/sshd_config /etc/ssh/sshd_config`.
2. It's not enough to just copy the file: its mode and permissions must be
   set, too.
3. There's no output telling the user which file is being copied.
4. The file will be copied even if there are no changes making it difficult to
   decide when to reload SSH server configuration.

In this case, it'd be better to use `file_copy` command provided by pocus. The
spell could look like this:

```sh
#!/bin/sh

# Load pocus commands.
. ./lib/pocus.commands

# Copy the file from $POCUS_SPELLBOOK_FILES, make it owned by user root and
# group wheel, ensure the right permissions.
file_copy /etc/ssh/sshd_config root:wheel 0644

# If sshd_config was copied by the command above then reload sshd. A real-world
# spell could use helper commands to tell the user SSH is being restarted (or
# that the restart was skipped), but they were omitted here for simplicity.
if file_any_copied /etc/ssh/sshd_config; then
   sudo systemctl restart sshd
fi
```

## Usage

Two things are needed to use pocus: a spellbook and a target definition.

The target definition must define `target_host`. It must be set to a value that
can be used to connect via SSH, e.g. `admin@web.example.com`. It's customary to
use the `.target` extension on the file name (e.g. `web.target`), but it's
not required.

The spellbook is a directory with two subdirectories: `spells` and `files`. Put
your spells into `spells` and any files they need to reference in `files`.
**It's recommended to make `files` mimic the hierarchy of the root file system
of the target server**.

After preparing the target definition and the spellbook you can run it via:

```
pocus <spellbook> <target>
```

### Example

Let's say we need to configure two web servers sitting behind a load balancer.
The servers must use identical SSH and nginx configuration.

The first target can be defined in a file named `web1.target` with the following
content:

```
target_host=admin@web1.example.com
```

The other target can be defined in a similar way in `web2.target`.

The spellbook needs two spells, `001_sshd` and `002_nginx`, plus `sshd_config`
and `nginx.conf`. All the files and directories needed would look like this:

```
web1.target
web2.target              (two target definitions)
web/                     (the web spellbook)
  spells/                (spells to cast)
    001_sshd             (SSH setup)
    002_nginx            (nginx setup)
  files/                 (files needed by the spells; maps to / on the server)
    etc/                 (maps to /etc on the server)
      ssh/               (maps to /etc/ssh on the server)
        sshd_config      (maps to /etc/ssh/sshd_config on the server)
      nginx/             (maps to /etc/nginx on the server)
        nginx.conf       (maps to /etc/nginx/nginx.conf on the server)
```

You can now run the `web` playbook on both targets:

```
pocus web web1.target
pocus web web2.target
```

## Commands

It's recommended that your spells use pocus-provided commands. In order to use
them start your spell with:

```
. ./lib/pocus.commands
```

The following commands are available:

- `file_copy <path> <owner> <mode>` - copies the file from spellbook files, sets ownership and permissions
- `file_create <path> <owner> <mode>` - touches the file, sets ownership and permissions
- `file_any_copied <path1> <path2> ...` - succeeds if any of the files were copied or created via `file_copy` or `file_create`; useful in conditional steps like reloading a server if it's configuration changed
- `directory_create <path> <owner> <mode>` - creates the directory, sets ownership and permissions
- `cron_install <user> <path>` - installs file at `<path>` (relative to spellbook files) as the crontab for `<user>`
- `user_change_home <user> <home>` - changes the home directory of `<user>` to `<home>`
- `openbsd_daemon_enable <name>` - enables an OpenBSD daemon
- `openbsd_package_install <name>` - installs an OpenBSD package via `pkg_add`
- `notice <text>` - prints a notice to standard output

## Design Goals

1. No YAML or XML programming!
2. Minimal dependencies on standard UNIX tooling.
3. User-friendly output.
4. Optimized for single-server setups, but applicable to other scenarios, too.
5. High portability across UNIX systems.

## Author

pocus is developed and maintained by [Greg Navis](https://www.gregnavis.com/).
