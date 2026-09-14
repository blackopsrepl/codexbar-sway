// Release configuration for commit-and-tag-version.
// Keeps the tracked application version surfaces in step so a release only
// needs `commit-and-tag-version`, never hand-edited version files.

const versionEnv = {
  filename: 'version.env',
  updater: {
    readVersion(contents) {
      const match = contents.match(/^MARKETING_VERSION=(.+)$/m);
      return match ? match[1].trim() : null;
    },
    writeVersion(contents, version) {
      return contents.replace(/^MARKETING_VERSION=.*$/m, `MARKETING_VERSION=${version}`);
    },
  },
};

const codexClientIdentity = {
  filename: 'lib/codexbar/providers/codex.rb',
  updater: {
    readVersion(contents) {
      const match = contents.match(/initialize_client\("codexbar-linux", "([^"]+)"\)/);
      return match ? match[1] : null;
    },
    writeVersion(contents, version) {
      return contents.replace(
        /(initialize_client\("codexbar-linux", ")[^"]+("\))/,
        `$1${version}$2`
      );
    },
  },
};

module.exports = {
  packageFiles: [versionEnv],
  bumpFiles: [versionEnv, codexClientIdentity],
  tagPrefix: 'v',
  releaseCommitMessageFormat: 'chore(release): {{currentTag}}',
  commitUrlFormat: 'https://github.com/blackopsrepl/codexbar-sway/commit/{{hash}}',
  compareUrlFormat: 'https://github.com/blackopsrepl/codexbar-sway/compare/{{previousTag}}...{{currentTag}}',
};
