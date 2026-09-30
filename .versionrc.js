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
  filename: 'lib/tokenmaxx/providers/codex.rb',
  updater: {
    // Accepts the pre-rebrand "codexbar-linux" identity so a bump from an
    // older checkout still works; writes are always the rebranded id.
    readVersion(contents) {
      const match = contents.match(/initialize_client\("(?:tokenmaxx|codexbar)-linux", "([^"]+)"\)/);
      return match ? match[1] : null;
    },
    writeVersion(contents, version) {
      return contents.replace(
        /initialize_client\("(?:tokenmaxx|codexbar)-linux", "[^"]+"\)/,
        `initialize_client("tokenmaxx-linux", "${version}")`
      );
    },
  },
};

module.exports = {
  packageFiles: [versionEnv],
  bumpFiles: [versionEnv, codexClientIdentity],
  tagPrefix: 'v',
  releaseCommitMessageFormat: 'chore(release): {{currentTag}}',
  commitUrlFormat: 'https://github.com/blackopsrepl/tokenmaxx/commit/{{hash}}',
  compareUrlFormat: 'https://github.com/blackopsrepl/tokenmaxx/compare/{{previousTag}}...{{currentTag}}',
};
