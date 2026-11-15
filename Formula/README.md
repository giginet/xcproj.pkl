# Homebrew tap

The release workflow generates `xcprojgen.rb` from `xcprojgen.rb.template` after
uploading the CLI archive. It commits the version, release URL, and SHA-256 to
`main` automatically. There is no installable formula until the first release;
the template intentionally contains no placeholder checksum for an unpublished
binary.

Edit the template to change installation behavior. Do not update the generated
formula before publishing a release. See the [release flow](../Docs/CI.md#releasing-cli-and-pkl-together).
