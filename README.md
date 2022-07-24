# Scribe install script
Scribe install script will install scribe CLI tools 
```
curl -sSfL https://raw.githubusercontent.com/scribe-security/misc/master/install.sh | sh
```

## Supported tools
* Gensbom - SBOM Generation tool
* Valint - validate supply chain integrity tool

## Usage
```
Usage: install.sh [-b] bindir [-d] [-t tool]
  -b install directory , Default - "/home/mikey/.scribe/bin/"
  -d debug log
  -t tool list 'tool:version', Default - "gensbom valint"
  -h usage

  Empty version will select the latest version.
```

### Custom install location
```
curl -sSfL https://raw.githubusercontent.com/scribe-security/misc/master/install.sh | sh -s -- -b /usr/local/bin
```

### Select specific tool and version
Selcting a tool version
```
curl -sSfL https://raw.githubusercontent.com/scribe-security/misc/master/install.sh | sh -s -- -d -t gensbom:2.1.114 -t valint:0.0.23
```

### Select single specific tool
Selcting a tool version
```
curl -sSfL https://raw.githubusercontent.com/scribe-security/misc/master/install.sh | sh -s -- -t gensbom
```
