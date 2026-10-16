[![CI](https://github.com/OpenIntegrationEngine/engine-docker/actions/workflows/ci.yaml/badge.svg)](https://github.com/OpenIntegrationEngine/engine-docker/actions/workflows/ci.yaml)
[![Publish](https://github.com/OpenIntegrationEngine/engine-docker/actions/workflows/publish.yaml/badge.svg)](https://github.com/OpenIntegrationEngine/engine-docker/actions/workflows/publish.yaml)
[![Latest image](https://img.shields.io/github/v/release/OpenIntegrationEngine/engine-docker?label=latest%20image)](https://github.com/OpenIntegrationEngine/engine-docker/releases/latest)
[![Newest image](https://img.shields.io/github/v/release/OpenIntegrationEngine/engine-docker?include_prereleases&label=newest)](https://github.com/OpenIntegrationEngine/engine-docker/releases)
[![Docker pulls](https://img.shields.io/docker/pulls/openintegrationengine/engine)](https://hub.docker.com/r/openintegrationengine/engine)
[![Image size](https://img.shields.io/docker/image-size/openintegrationengine/engine/latest)](https://hub.docker.com/r/openintegrationengine/engine/tags)

<a name="quick-reference"></a>
# Quick Reference

#### Where to get help:

- 🌐 **Website**: [openintegrationengine.org](https://openintegrationengine.org)
- 💬 **Discord**: [Join our server](https://discord.gg/azdehW2Zrx)
- 📂 **GitHub Repo**: [github.com/OpenIntegrationEngine/engine](https://github.com/OpenIntegrationEngine/engine)

#### How to file issues:

https://github.com/OpenIntegrationEngine/engine/issues

Please do your best to include the following information in your issue:
* The exact commit hash of the code you are using
* The commands you executed to build or run the image
* The output of the command you executed (Hint: add `--progress=plain` to your `docker` command to see the full output)
* Use [Markdown](https://guides.github.com/features/mastering-markdown/) to format your issue text, ESPECIALLY if you are including code snippets or command output. This will make it easier for us to read and understand your issue.

------------

<a name="what-is-oie"></a>
# What is Open Integration Engine

An open-source message integration engine focused on healthcare. For more information please visit [openintegrationengine.org](https://openintegrationengine.org).

OpenIntegrationEngine is a community-driven project that continues the legacy of Mirth Connect, providing a flexible, open platform for managing healthcare interfaces. It supports a wide range of
healthcare standards and protocols, enabling seamless integration between disparate systems.

OpenIntegrationEngine is designed to be vendor-neutral, allowing healthcare organizations to connect their systems without being locked into proprietary solutions. It offers a user-friendly interface
for building, deploying, and managing interfaces, along with powerful features for real-time monitoring and alerting.

------------

<a name="supported-tags"></a>
# Supported tags

Every image is built for `linux/amd64` and `linux/arm64` with Java 21.

| Variant | Base image | Tags, e.g. for 4.6.0 |
|---|---|---|
| JRE on Ubuntu 24.04 (default) | `eclipse-temurin:21-jre-noble` | `latest`, `4.6`, `4.6.0`, `4.6.0-jre21-noble`, `4.6.0-r1` |
| JDK on Ubuntu 24.04 | `eclipse-temurin:21-jdk-noble` | `latest-jdk`, `4.6-jdk`, `4.6.0-jdk`, `4.6.0-jdk21-noble`, `4.6.0-jdk-r1` |
| JRE on Alpine | `eclipse-temurin:21-jre-alpine` | `latest-alpine`, `4.6-alpine`, `4.6.0-alpine`, `4.6.0-jre21-alpine`, `4.6.0-alpine-r1` |

Use the default unless you need JDK tools such as `jcmd` for troubleshooting, or a smaller Alpine image.

**Which tags move:**
- `4.6.0-r1` (and `4.6.0-jre21-noble-r1`, ...) is one image revision and never changes. **Pin this, or the image digest, in production.**
- `4.6.0` is the newest promoted revision of 4.6.0. New revisions follow base image, Java and packaging updates.
- `4.6` is the newest promoted patch of 4.6, and `latest` the newest stable version. There is no `4` tag.
- `4.7.0-rc1`, `rc`, `rc-jdk` and `rc-alpine` are upstream release candidates, for testing only.

`-rN` is an image revision; `-rcN` is an upstream release candidate. `4.7.0-rc1-r2` is the second image revision of 4.7.0-rc1.

The older tag names `-ubuntu`, `-ubuntu-jre`, `-ubuntu-jdk` and `-alpine-jre` (e.g. `latest-ubuntu`, `4.6.0-alpine-jre`) still move with their equivalents above. `latest-alpine-jdk` is no
longer updated, and the 4.5.2 tags are not rebuilt. How images are published and promoted is described in [docs/RELEASING.md](docs/RELEASING.md).

#### How new images are released
1. Within an hour of an upstream release, a **candidate** such as `4.7.0-r1` is built, tested, signed and listed as a [pre-release](https://github.com/OpenIntegrationEngine/engine-docker/releases).
2. It soaks for 48 hours if it matches the last release candidate or is a rebuild (e.g. base image updates), otherwise 7 days. Release candidates (`4.7.0-rc1`) don't soak.
3. It is **promoted**: `4.7.0`, `4.7`, `latest`, ... move to it.

Please test candidates, and report problems with the [image candidate problem](https://github.com/OpenIntegrationEngine/engine-docker/issues/new?template=image-candidate-problem.yml)
template; a maintainer can hold the promotion until it's fixed.

#### Upgrading from the 4.5.2 images
- Java 21 instead of Java 17.
- `latest` is now the Ubuntu JRE image; it used to be Alpine. Use `latest-alpine` to stay on Alpine.
- Engine runs as `engine`, uid 1000, so existing appdata volumes keep working. Only `appdata`, `conf`, `custom-extensions`, `extensions`, `logs` and `server-launcher-lib` under `/opt/engine` are
  writable.
- The JVM options secret is `oieserver_vmoptions`; `mcserver_vmoptions` still works.

------------

<a name="how-to-use"></a>
# How to use this image

<a name="start-engine"></a>
## Start an OpenIntegrationEngine instance

Quickly start OpenIntegration using embedded Derby database and all configuration defaults. At a minimum you will likely want to use the `-p` option to expose the 8443 port so that you can log in with
the Administrator GUI or CLI:

```bash
docker run -p 8443:8443 openintegrationengine/engine
```

You can also use the `--name` option to give your container a unique name, and the `-d` option to detach the container and run it in the background:

```bash
docker run --name myengine -d -p 8443:8443 openintegrationengine/engine
```

To run a different base image, specify a tag at the end:

```bash
docker run --name myengine -d -p 8443:8443 openintegrationengine/engine:latest-alpine
```

To run using a specific architecture, specify it using the `--platform` argument:

```bash
docker run --name myengine -d -p 8443:8443 --platform linux/arm64 openintegrationengine/engine
```

Look at the [Environment Variables](#environment-variables) section for more available configuration options.

------------

<a name="using-docker-compose"></a>
## Using [`docker stack deploy`](https://docs.docker.com/engine/reference/commandline/stack_deploy/) or [`docker compose`](https://github.com/docker/compose)

With `docker stack` or `docker compose` you can easily set up and launch multiple related containers. For example, you might want to launch both Engine *and* a PostgreSQL database to run alongside it.

```bash
docker compose -f stack.yml up
```

Here's an example `stack.yml` file you can use:

```yaml
services:
  engine:
    image: openintegrationengine/engine
    environment:
      - DATABASE=postgres
      - DATABASE_URL=jdbc:postgresql://db:5432/enginedb
      - DATABASE_MAX_CONNECTIONS=20
      - DATABASE_USERNAME=enginedb
      - DATABASE_PASSWORD=enginedb
      - DATABASE_MAX_RETRY=2
      - DATABASE_RETRY_WAIT=10000
      - KEYSTORE_STOREPASS=docker_storepass
      - KEYSTORE_KEYPASS=docker_keypass
      - VMOPTIONS=-Xmx512m
    ports:
      - "8080:8080/tcp"
      - "8443:8443/tcp"
    depends_on:
      - db

  db:
    image: postgres
    environment:
      - POSTGRES_USER=enginedb
      - POSTGRES_PASSWORD=enginedb
      - POSTGRES_DB=enginedb
    ports:
      - "5432:5432/tcp"
```

------------

<a name="environment-variables"></a>
## Environment Variables

You can use environment variables to configure the [mirth.properties](https://github.com/openintegrationengine/engine/blob/development/server/conf/mirth.properties) file or to add custom JVM options.

### Setting Environment Variables

To set environment variables, use the `-e` option for each variable on the command line:

```bash
docker run -e DATABASE='derby' -p 8443:8443 openintegrationengine/engine
```

You can also use a separate file containing all of your environment variables using the `--env-file` option. For example let's say you create a file **myenvfile.txt**:

```bash
DATABASE=postgres
DATABASE_URL=jdbc:postgresql://serverip:5432/enginedb
DATABASE_USERNAME=postgres
DATABASE_PASSWORD=postgres
DATABASE_MAX_RETRY=2
DATABASE_RETRY_WAIT=10000
KEYSTORE_STOREPASS=changeme
KEYSTORE_KEYPASS=changeme
VMOPTIONS=-Xmx512m
```

```bash
docker run --env-file=myenvfile.txt -p 8443:8443 openintegrationengine/engine
```

------------

<a name="common-mirth-properties-options"></a>
### Common mirth.properties options

<a name="env-database"></a>
#### `DATABASE`

The database type to use for the Open Integration Engine backend database. Options:

* derby
* mysql
* postgres
* oracle
* sqlserver

<a name="env-database-url"></a>
#### `DATABASE_URL`

The JDBC URL to use when connecting to the database. For example:
* `jdbc:postgresql://serverip:5432/enginedb`

<a name="env-database-username"></a>
#### `DATABASE_USERNAME`

The username to use when connecting to the database. If you don't want to use an environment variable to store sensitive information like this, look at the [Using Docker Secrets](#using-docker-secrets) section below.

<a name="env-database-password"></a>
#### `DATABASE_PASSWORD`

The password to use when connecting to the database. If you don't want to use an environment variable to store sensitive information like this, look at the [Using Docker Secrets](#using-docker-secrets) section below.

<a name="env-database-max-connections"></a>
#### `DATABASE_MAX_CONNECTIONS`

The maximum number of connections to use for the internal messaging engine connection pool.

<a name="env-database-max-retry"></a>
#### `DATABASE_MAX_RETRY`

On startup, if a database connection cannot be made for any reason, Engine will wait and attempt again this number of times. By default, will retry 2 times (so 3 total attempts).

<a name="env-database-retry-wait"></a>
#### `DATABASE_RETRY_WAIT`

The amount of time (in milliseconds) to wait between database connection attempts. By default, will wait 10 seconds between attempts.

<a name="env-keystore-storepass"></a>
#### `KEYSTORE_STOREPASS`

The password for the keystore file itself. If you don't want to use an environment variable to store sensitive information like this, look at the [Using Docker Secrets](#using-docker-secrets) section below.

<a name="env-keystore-keypass"></a>
#### `KEYSTORE_KEYPASS`

The password for the keys within the keystore, including the server certificate and the secret encryption key. If you don't want to use an environment variable to store sensitive information like this,
look at the [Using Docker Secrets](#using-docker-secrets) section below.

<a name="env-keystore-type"></a>
#### `KEYSTORE_TYPE`

The type of keystore.

<a name="env-session-store"></a>
#### `SESSION_STORE`

If set to true, the web server sessions are stored in the database. This can be useful in situations where you have multiple Engine servers (connecting to the same database) clustered behind a load
balancer.

<a name="env-vmoptions"></a>
#### `VMOPTIONS`

A comma-separated list of JVM options, for example `VMOPTIONS=-Xmx512m,-Duser.timezone=UTC`. On every start they are written to `conf/docker.vmoptions`, which is read after the default options, so
they override them (the default heap is `-Xmx256m`). Restarting the container doesn't add duplicates.

<a name="env-delay"></a>
#### `DELAY`

The number of seconds the entrypoint script waits before starting Engine. It doesn't check the database; use it to give a database that starts at the same time as Engine time to come up.

<a name="env-keystore-download"></a>
#### `KEYSTORE_DOWNLOAD`

A URL location of a Engine keystore file. This file will be downloaded into the container and Engine will use it as its keystore.

If any of the downloads (`KEYSTORE_DOWNLOAD`, `EXTENSIONS_DOWNLOAD`, `CUSTOM_JARS_DOWNLOAD`) fails, the container exits with an error instead of starting Engine without it.

<a name ="env-extensions-download"></a>
#### `EXTENSIONS_DOWNLOAD`

A URL location of a zip file containing Engine extension zip files. The extensions will be installed on the Engine server.

<a name ="env-custom-jars-download"></a>
#### `CUSTOM_JARS_DOWNLOAD`

A URL location of a zip file containing JAR files. The JAR files will be installed into the `server-launcher-lib` folder on the Engine server, so they will be added to the server's classpath.

<a name="env-allow-insecure"></a>
#### `ALLOW_INSECURE`

Allow insecure SSL connections when downloading files during startup. This applies to keystore downloads, plugin downloads, and server library downloads. By default, insecure connections are disabled,
but you can enable this option by setting `ALLOW_INSECURE=true`.

<a name="env-server-id"></a>
#### `SERVER_ID`

Set the `server.id` to a specific value. Use this to preserve or set the server ID across restarts and deployments. Using the env-var is preferred over storing `appdata` persistently

------------

<a name="other-mirth-properties-options"></a>
### Other mirth.properties options

Other options in the mirth.properties file can also be changed. Any environment variable starting with the `_MP_` prefix will set the corresponding value in mirth.properties. Replace `.` with a single
underscore `_` and `-` with two underscores `__`.

Values are written to mirth.properties exactly as given, from both named and `_MP_` variables. mirth.properties is a Java properties file, so a backslash there starts an escape sequence; write `\\` for a
literal backslash. A value containing a newline stops the container with an error.

Examples:

* Set the server TLS protocols to only allow TLSv1.2 and 1.3:
    * In the mirth.properties file:
        * `https.server.protocols = TLSv1.3,TLSv1.2`
    * As a Docker environment variable:
        * `_MP_HTTPS_SERVER_PROTOCOLS='TLSv1.3,TLSv1.2'`

* Set the max connections for the read-only database connection pool:
    * In the mirth.properties file:
        * `database-readonly.max-connections = 20`
    * As a Docker environment variable:
        * `_MP_DATABASE__READONLY_MAX__CONNECTIONS='20'`

------------

<a name="using-docker-secrets"></a>
## Using Docker Secrets

For sensitive information such as the database/keystore credentials, instead of supplying them as environment variables you can use a [Docker Secret](https://docs.docker.com/engine/swarm/secrets/).
There are two secret names this image supports:

##### mirth_properties

If present, any properties in this secret will be merged into the mirth.properties file.

##### oieserver_vmoptions

If present, the JVM options in this secret (one per line) are applied after `VMOPTIONS`. The older name `mcserver_vmoptions` is also accepted.

------------

Secrets are supported with [Docker Swarm](https://docs.docker.com/engine/swarm/secrets/), but you can also use them with [`docker compose`](#using-docker-compose).

For example let's say you wanted to set `keystore.storepass` and `keystore.keypass` in a secure way. You could create a new file, **secret.properties**:

```bash
keystore.storepass=changeme
keystore.keypass=changeme
```

Then in your `compose.yaml`:

```yaml
services:
  engine:
    image: openintegrationengine/engine
    environment:
      - VMOPTIONS=-Xmx512m
    secrets:
      - mirth_properties
    ports:
      - "8080:8080/tcp"
      - "8443:8443/tcp"

secrets:
  mirth_properties:
    file: /local/path/to/secret.properties
```

The **secrets** section at the bottom specifies the local file location for each secret.  Change `/local/path/to/secret.properties` to the correct local path and filename.

Inside the configuration for the Engine container there is also a **secrets** section that lists the secrets you want to include for that container.

------------

<a name="custom-ca-certificates"></a>
## Trusting additional CA certificates

To make Engine trust extra CA certificates, for example for a database or HTTPS endpoint with an internal CA, mount a directory of PEM certificates at `/certificates` and set
`USE_SYSTEM_CA_CERTS=1`. This uses the [Eclipse Temurin](https://hub.docker.com/_/eclipse-temurin) base image's support for custom certificates; because Engine doesn't run as root, the certificates
are added to a temporary copy of the Java truststore when the container starts.

```bash
docker run -e USE_SYSTEM_CA_CERTS=1 -v /local/path/to/certificates:/certificates:ro -p 8443:8443 openintegrationengine/engine
```

------------

<a name="security"></a>
## Running with fewer privileges

Engine runs as the unprivileged user `engine` (uid 1000) and doesn't need any Linux capabilities. We recommend dropping them and blocking privilege escalation:

```bash
docker run --cap-drop ALL --security-opt no-new-privileges -p 8443:8443 openintegrationengine/engine
```

In `compose.yaml`:

```yaml
services:
  engine:
    image: openintegrationengine/engine
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
```

------------

<a name="using-volumes"></a>
## Using Volumes

<a name="the-appdata-folder"></a>
#### The appdata folder

The application data directory (appdata) stores configuration files and temporary data created by Engine after starting up. This usually includes the keystore file and the `server.id` file that stores
your server ID. If you are launching Engine as part of a stack/swarm, it's possible the container filesystem is already being preserved. But if not, you may want to consider mounting a **volume** to
preserve the appdata folder.

```bash
docker run -v /local/path/to/appdata:/opt/engine/appdata -p 8443:8443 openintegrationengine/engine
```

The `-v` option makes a local directory from your filesystem available to the Docker container. Create a folder on your local filesystem, then change the `/local/path/to/appdata` part in the example
above to the correct local path.

You can also configure volumes as part of your `compose.yaml`:

```yaml
services:
  engine:
    image: openintegrationengine/engine
    volumes:
      - ~/Documents/appdata:/opt/engine/appdata
```

------------

<a name="additional-extensions"></a>
#### Additional extensions

The entrypoint script will automatically look for any `.zip` files in the `/opt/engine/custom-extensions` folder and unzip them into the extensions folder before Engine starts up.
So to launch Engine with any additional extensions not included in the base application, do this:

```bash
docker run -v /local/path/to/custom-extensions:/opt/engine/custom-extensions -p 8443:8443 openintegrationengine/engine:latest-ubuntu-jre
```

Create a folder on your local filesystem containing the ZIP files for your additional extensions. Then change the `/local/path/to/custom-extensions` part in the example above to the correct local path.

As with the appdata example, you can also configure this volume as part of your `compose.yaml`.

------------

## Known Limitations

Currently, only the Debian flavored images support the newest authentication scheme in MySQL 8. All others (the Alpine based images) will need the following to force the MySQL database container to
start using the old authentication scheme:

```yaml
command: --default-authentication-plugin=mysql_native_password
```

Example:

```yaml
  db:
    image: mysql
    command: --default-authentication-plugin=mysql_native_password
    environment:
      ...
```

------------

## Building images

The images are defined in [`deploy/docker-bake.hcl`](deploy/docker-bake.hcl) and built with [Docker Bake](https://docs.docker.com/build/bake/). There are three variants, all on Java 21 for `linux/amd64` and `linux/arm64`:

| Bake target  | Base image                       |
|--------------|----------------------------------|
| `jre-noble`  | `eclipse-temurin:21-jre-noble`   |
| `jdk-noble`  | `eclipse-temurin:21-jdk-noble`   |
| `jre-alpine` | `eclipse-temurin:21-jre-alpine`  |

Run these commands in the `deploy/` directory:
```sh
# Show the resolved build definition
docker buildx bake --print

# Build every variant for both platforms
docker buildx bake

# Build one variant for your own platform and load it as oie-engine:local-jre-noble
docker buildx bake jre-noble --set '*.platform=linux/amd64' --load
```

Variables in `docker-bake.hcl` can be overridden from the environment. To build a different OIE release, set its version and the tarball's sha256 from the release's `sha256sums` file:
```sh
OIE_VERSION=4.6.0-rc1 OIE_RELEASE_SHA256=<sha256> docker buildx bake
```

The build fails if the downloaded tarball doesn't match the checksum. It also fails if the base image contains files outside `/opt/engine` owned by uid or gid 1000, the uid the engine runs as.

Building for a platform other than your own needs QEMU emulation, e.g. `docker run --privileged --rm tonistiigi/binfmt --install arm64`.

------------

<a name="verifying"></a>
# Verifying images

Every image revision is signed with [cosign](https://docs.sigstore.dev/cosign/verifying/verify/) v3 keyless signing (Sigstore bundle format, verify with cosign v3) by this repository's publish workflow, and carries an SBOM and
[SLSA provenance](https://docs.docker.com/build/metadata/attestations/slsa-provenance/) made by BuildKit. Signatures are recorded in the public [Sigstore transparency log](https://search.sigstore.dev/).

```bash
cosign verify docker.io/openintegrationengine/engine:4.6.0 \
  --certificate-identity https://github.com/OpenIntegrationEngine/engine-docker/.github/workflows/publish.yaml@refs/heads/main \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com

docker buildx imagetools inspect openintegrationengine/engine:4.6.0 --format '{{json .Provenance}}'
docker buildx imagetools inspect openintegrationengine/engine:4.6.0 --format '{{json .SBOM}}'
```

The provenance records the engine-docker commit and workflow run, the upstream tarball's URL and SHA-256 (checked during the build), and the base image digests. It doesn't show how the
upstream tarball was built; its SHA-256 comes from the upstream release's `sha256sums`. See Docker's [attestation](https://docs.docker.com/build/metadata/attestations/),
[SBOM](https://docs.docker.com/build/metadata/attestations/sbom/) and [`imagetools inspect`](https://docs.docker.com/reference/cli/docker/buildx/imagetools/inspect/) docs.

To enforce the signature in Kubernetes, use the identity and issuer above with [Kyverno](https://kyverno.io/docs/policy-types/cluster-policy/verify-images/sigstore/):

```yaml
verifyImages:
  - imageReferences: ["docker.io/openintegrationengine/engine*"]
    type: SigstoreBundle
    attestors:
      - entries:
          - keyless:
              subject: https://github.com/OpenIntegrationEngine/engine-docker/.github/workflows/publish.yaml@refs/heads/main
              issuer: https://token.actions.githubusercontent.com
```

or the Sigstore [policy-controller](https://docs.sigstore.dev/policy-controller/overview/) (not yet tested with bundle-format signatures):

```yaml
apiVersion: policy.sigstore.dev/v1beta1
kind: ClusterImagePolicy
metadata:
  name: openintegrationengine
spec:
  images:
    - glob: "index.docker.io/openintegrationengine/engine**"
  authorities:
    - keyless:
        identities:
          - issuer: https://token.actions.githubusercontent.com
            subject: https://github.com/OpenIntegrationEngine/engine-docker/.github/workflows/publish.yaml@refs/heads/main
```

------------

<a name="license"></a>
# License

The Dockerfiles, entrypoint script, and any other files used to build these Docker images are Copyright © NextGen Healthcare and OpenIntegrationEngine contributors.
They are licensed under the [Mozilla Public License 2.0](https://www.mozilla.org/en-US/MPL/2.0/).
