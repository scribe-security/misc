# Docker Policy Plugin: Enforce Supply-Chain Policies on Container Images

This Docker CLI plugin, powered by the Valint tool from Scribe Security, evaluates and enforces supply-chain policies on container images. It helps ensure that your containerized applications meet compliance standards and includes optional configuration for SBOM generation and debug logging.

## Install

Scribe install script will install scribe docker CLI scripts 

```bash
curl -sSfL https://raw.githubusercontent.com/scribe-security/misc/master/docker-cli-plugin/install.sh | sh
```


## Usage

Run the plugin from the Docker CLI with the policy subcommand, followed by Valint arguments:

```bash
docker policy <image> --rule sbom/fresh-sbom@v1 [options]
```

## Plugin Options

* `-d`, `--output-directory`: Specify a directory for output files (e.g., metadata).
* `-x`, `--debug`: Enable debug mode for verbose output.
* `--verify-only`: Run in verification-only mode, skipping additional checks.
* `--files`: Include a detailed SBOM analysis with component files.

## Policy Configuration

Policies can be managed as code. Policies and rules can be stored and managed by an organization's security team. By default, we provide a sample policy bundle with a subset of policies and rules. See the sample policies [here](https://github.com/scribe-public/sample-policies).

For more detailed information about policy management and rules, refer to the [Scribe Security documentation](https://scribe-security.netlify.app/docs/guides/enforcing-sdlc-policy).

The plugin provides the capability to evaluate a set of rules from the command line or an entire policy file.

### Rule Option

The plugin provides access to a set of rules that can be combined with arguments:

```bash
docker policy ubuntu:latest --rule sbom/fresh-sbom@v1
```

### Policy Option

The plugin allows you to evaluate an entire policy through a file or remote access:

```bash
docker policy ubuntu:latest --policy image-policy@discovery
```

## Valint Options

Valint includes a wide range of options. For more details, refer to the [Valint documentation](https://scribe-security.netlify.app/docs/valint/).

### Example Commands TBD

**Basic Policy Evaluation:**

```bash
docker policy mongo-express:latest --rule sbom/fresh-sbom@v1
```

**Enabling Debug Mode and Output Directory:**

```bash
docker policy mongo-express:latest --rule sbom/fresh-sbom@v1 -x -d /path/to/output
```

**Verification Mode with SBOM Analysis:**

```bash
docker policy mongo-express:latest --rule sbom/fresh-sbom@v1 --verify-only --files
```

### Environment Variables

- `ONLY_VERIFY`: Run in verification-only mode (true by default).
- `INCLUDE_FILES`: Include file components in SBOM generation (false by default).
- `DEBUG_MODE`: Enable verbose output (false by default).
```

