#!/bin/sh
set -e
fixtures="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/SourceFixtures"
app_fixtures="$fixtures/Don't forget"
widget_fixtures="$fixtures/Don't forgetWidget"
mkdir -p "$app_fixtures" "$widget_fixtures"
for source in "$SRCROOT/Don't forget"/*.swift; do
    cp -X -f "$source" "$app_fixtures/"
done
cp -X -f "$SRCROOT/Don't forget/Localizable.xcstrings" "$app_fixtures/"
cp -X -f "$SRCROOT/Don't forgetWidget/Localizable.xcstrings" "$widget_fixtures/"
touch "$fixtures/.stamp"

