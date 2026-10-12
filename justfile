app := "Nanocast Dev"

# Build the Debug channel and restart it. The installed Nanocast keeps running untouched.
dev:
    xcodebuild -project Nanocast.xcodeproj -scheme Nanocast -configuration Debug \
        -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -quiet build
    -pkill -x "{{app}}"
    while pgrep -x "{{app}}" > /dev/null; do sleep 0.1; done
    open "build/DerivedData/Build/Products/Debug/{{app}}.app"
