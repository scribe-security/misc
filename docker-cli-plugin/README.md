# Scribe Docker CLI plugins 
Scribe offers Docker CLI plugins for embedding evidence collecting and integrity verification to your workflows. \
Actions are are wrappers to provided CLI tools.
Plugins allow you to generate SBOMS as w

## Install
Scribe install script will install scribe docker CLI scripts 
```
curl -sSfL https://raw.githubusercontent.com/scribe-security/misc/master/docker-cli-plugin/install.sh | sh
```

## Gensbom
Gensbom is a CLI tool by Scribe which analyzes components and creates SBOMs. \
Gensbom SBOMs are populated CycloneDX SBOM with target packages, files, layers, and dependencies. \
Gensbom also supports signed SBOM as populated in-toto attestations using the cocosign framework. Scribe uses the **cocosign** library we developed to deal with digital signatures for signing and verification.

## Supported plugins
### Bom
Command analyzes image components and file systems. \
It can be used for multiple targets and output formats. \
Further more command can be used to sign the resulting sbom.

```
docker bom busybox:latest -v
```

### basic usage
Gensbom allows you to create SBOMs in multiple flavors.

<details>
  <summary> CycloneDX </summary>

CycloneDX SBOM with all the available components.

```bash
docker bom busybox:latest -o json
docker bom busybox:latest -o xml
``` 
</details>

<details>
  <summary> Statement </summary>

In-toto statement is basically an unsigned attestation.
Output can be useful if you like to connect to other attestation frameworks such as `cosign`.

```bash
docker bom busybox:latest -o statement
``` 
</details>

<details>
  <summary> Attestations </summary>

In-toto Attestation output, default via keyless Sigstore flow 
```bash
docker bom busybox:latest -o attest
``` 

</details>

<details>
  <summary> Metadata only </summary>

You may select which components groups are added to your SBOM.
For example you may use Gensbom to simply sign and verify your images, you only really need the `metadata` group.
Note metadata is implicate (BOM must include something).
```bash
docker bom busybox:latest --components metadata #Only include the target metadata
docker bom busybox:latest --components packages #Only include packages
docker bom busybox:latest --components packages,files,dep #Include packages files and there related relationship.
``` 
</details>

<details>
  <summary> Attach external data </summary>

Gensbom allows you to include external files content as part of the reported evidence.
For example you may use Gensbom to include a external security report in your SBOM.
```bash
docker bom busybox:latest -vv -A **/some_report.json
``` 
</details>


### Verify
Command finds and verifies signed SBOM for image components and file systems. \
It can be used for multiple targets and output formats.

```
docker verify busybox:latest -v
```


# Scribe service
Scribe provides a set of services allowing you to secure your supply chain. \
Use configuration/args to set `scribe.client-id` (`-U`), `scribe.client-secret` (`-P`) provided by scribe.
Lastly enable scribe client using `-E` flag.
Gensbom will upload/download SBOM to your scribe account.

<details>
  <summary> Signing </summary>

You can use scribe signing service to sign.
Scribe will sign SBOM for you and provide access to the signed attestation.
Scribe service will allow you to verify against Scribe Root CA against your account identity.
You may can use the default Scribe `cocosign` configuration flag.

**Scribe root cert \<TBD public link\> to verify against.**

```bash
docker bom busybox:latest -E --U ${CLIENT_ID} -P ${CLIENT_SECRET} -o attest -v
docker verify busybox:latest -E --U ${CLIENT_ID} -P ${CLIENT_SECRET} -v
```
</details>

<details>
  <summary> Integrity </summary>

You can use scribe service run  integrity policies against your evidence.


```bash
docker bom busybox:latest -E --U ${CLIENT_ID} -P ${CLIENT_SECRET} -v
```
</details>

# Dev
See details [CLI documentation - dev](docs/dev.md)
