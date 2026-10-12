#!/bin/bash

package_json="src/package.json"

update_version() {
  local new_version=$1
  jq --arg new_version "$new_version" '.version = $new_version' "$package_json" > tmp.json && mv tmp.json "$package_json"
}

current_version=$(jq -r '.version' "$package_json")
echo "Current version: $current_version"

read -r -p "Enter the new version (following SemVer): " new_version

semver_regex='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-(0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*)(\.(0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*))*)?(\+[0-9a-zA-Z-]+(\.[0-9a-zA-Z-]+)*)?$'

if ! [[ "$new_version" =~ $semver_regex ]]; then
  echo "Invalid version format. Please use SemVer format (e.g., 1.0.0 or 1.0.0-alpha)."
  exit 1
fi

update_version "$new_version"
echo "Updated package.json to version $new_version"

echo "----"
echo "Make sure to stage any changes before proceeding (e.g. Changelog updates)."
echo "----"

echo "If you did everything press 'y' to commit the changes and create a new tag"
read -r -p "Do you want to continue? (y/n): " confirm

if [ "$confirm" != "y" ]; then
  echo "Aborted."
  exit 1
fi

git add "$package_json"
git commit -m "Bump version to $new_version"
echo "Committed the changes"

git tag -a "v$new_version" -m "Release version $new_version"
echo "Created Git tag v$new_version"

git push origin main --follow-tags
echo "Pushed Git commit and tag v$new_version to remote repository"
