# ccloud-deployment-automation

This repository contains scripts and automations to facilitate cCloud deployment with cloud service providers such as Amazon Web Services (AWS), Microsoft Azure, and Google Cloud Platform (GCP).

The content here is meant to supplement officially released cPacket documentation and software for cCloud.

## Getting started

Clone this repository and run a script.
For instance,

```bash
git clone https://github.com/mbrightcpacket/ccloud-deployment-automation
cd getting-started
./welcome.sh -h
```

Alternatively, download a specific script using [GitHub's 'Raw' button][raw].

```bash
curl -s -O https://raw.githubusercontent.com/cPacketNetworks/ccloud-deployment-automation/main/getting-started/welcome.sh
chmod 755 welcome.sh
./welcome.sh
```

## Permalinks

In order to better organize and maintain the content of the repository, the maintainers may occasionally change the file and directory layout.

A specific version of a file can be obtained by using [GitHub permalinks][permalinks] in combination with the 'Raw' button.

```bash
curl -s -O https://raw.githubusercontent.com/cPacketNetworks/ccloud-deployment-automation/25fc43614d65fcf8f038da7a14ab929ca0beb7ee/getting-started/welcome.sh
chmod 755 welcome.sh
./welcome.sh
```

## Documentation

Each script or automation in this repository should be contained in its own directory/folder along with a `README.md` and any docs and diagrams.

## Contributing and reporting bugs

The development team would love your feedback to help improve the items in this repository.
See the [CONTRIBUTING.md](/CONTRIBUTING.md) guide.

[raw]: https://docs.github.com/en/repositories/working-with-files/using-files/viewing-a-file
[permalinks]: https://docs.github.com/en/repositories/working-with-files/using-files/getting-permanent-links-to-files
