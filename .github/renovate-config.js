const helmRegex = {
  customType: "regex",
  datasourceTemplate: "helm",
  matchStringsStrategy: "combination",
};

module.exports = {
  username: "renovate[bot]",
  gitAuthor: "Renovate Bot <bot@renovateapp.com>",
  onboarding: false,
  platform: "github",
  forkProcessing: "disabled",
  dryRun: null,
  enabledManagers: ["custom.regex"],
  customManagers: [
    {
      customType: "regex",
      matchStringsStrategy: "any",
      fileMatch: [
        "\\.github/workflows/.+\\.(yaml|yml)$",
        "\\.github/actions/.+\\.(yaml|yml)$",
        "charts/.+/values\\.yaml$",
        "charts/.+/Chart\\.yaml$",
        ".+/templates/.+\\.(yaml|yml)$",
        ".+/config/.+\\.(yaml|yml)$"
      ],
      matchStrings: [
        // Original patterns
        '# renovate:\\s+?datasource=(?<datasource>\\S+?)\\s+?depName=(?<depName>\\S+?)\\s+?(default|(?i:.*version))\\s?(:|=|:=|\\?=)\\s+"?(?<currentValue>\\S+?)"\\s',
        '# renovate:\\s+?datasource=(?<datasource>\\S+?)\\s+?depName=(?<depName>\\S+?)\\s*\\n\\s*targetRevision:\\s*"?(?<currentValue>[^"\\s]+)"?',
        '# renovate:\\s+?datasource=(?<datasource>\\S+?)\\s+?registryUrl=(?<registryUrl>\\S+?)\\s+?depName=(?<depName>\\S+?)\\s*\\n\\s*targetRevision:\\s*"?(?<currentValue>[^"\\s]+)"?',
        '# renovate:\\s+?datasource=(?<datasource>\\S+?)\\s+?depName=(?<depName>\\S+?)\\s*\\n\\s*image:\\s*\\S+?:(?<currentValue>\\S+)',
        // New patterns for values.yaml files - tag field for separated repository/tag format
        '# renovate:\\s+?datasource=(?<datasource>\\S+?)\\s+?depName=(?<depName>\\S+?)\\s*\\n\\s*tag:\\s*"?(?<currentValue>[^"\\s]+?)"?\\s*$',
        // Helm chart versions in values.yaml
        '# renovate:\\s+?datasource=(?<datasource>\\S+?)\\s+?depName=(?<depName>\\S+?)\\s+?registryUrl=(?<registryUrl>\\S+?)\\s*\\n\\s*version:\\s*(?<currentValue>\\S+)',
        '# renovate:\\s+?datasource=(?<datasource>\\S+?)\\s+?depName=(?<depName>\\S+?)\\s+?registryUrl=(?<registryUrl>\\S+?)\\s*\\n\\s*chart_version:\\s*(?<currentValue>\\S+)',
      ],
    },
  ],
  packageRules: [
    {
      matchDatasources: ["helm", "docker", "github-releases"],
    },
  ],
};
