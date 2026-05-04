# skill_install_klingai_api

Installer for the official `klingai_api_skill`.

It installs the skill into the OpenClaw workspace, imports the Kling API Access Key and Secret Key into the skill's default credentials store, and creates a workspace link for `klingai_api_skill`.

## Usage

```bash
export KLING_ACCESS_KEY_ID='your-access-key-id'
export KLING_SECRET_ACCESS_KEY='your-secret-access-key'
./setup.sh
```

Aliases:

- `KLING_API_KEY` -> `KLING_ACCESS_KEY_ID`
- `KLING_SECRET_KEY` or `KLING_API_SECRET` -> `KLING_SECRET_ACCESS_KEY`

`KLING_API_KEY='access:secret'` is also accepted for simple renderers that only provide one API-key field.

Optional:

- `KLING_API_BASE=https://api-singapore.klingai.com` or `https://api-beijing.klingai.com`
- `KLING_STORAGE_ROOT=/path/to/kling-config`

Defaults inside the OpenClaw container:

- `CONTAINER_NAME=openclaw`
- `OPENCLAW_HOME=$HOME/.openclaw`
- `WORKSPACE_DIR=$OPENCLAW_HOME/workspace`
- `SKILLS_DIR=$OPENCLAW_HOME/skills`
- `REPO_URL=https://github.com/puboc/klingai_api_skill.git`
- `REPO_REF=main`

If run on the host and an `openclaw` container exists, the installer execs itself inside that container. It also creates a convenience symlink at `$WORKSPACE_DIR/skills/klingai_api_skill`.
