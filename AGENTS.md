# rules

no need to run xcodebuild
no need to write a summary
just change the code and reply "----------> DONE"

example of bad:

xcodebuild -project macos-app.xcodeproj -scheme macos-app -configuration Debug build
  └ Command line invocation:
        /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project macos-app.xcodeproj -scheme macos-app
    … +174 lines (ctrl + t to view transcript)
    ** BUILD SUCCEEDED **


• Ran git status --short
  └  M macos-app/ContentView.swift
     M macos-app/LocalAPIServer.swift

• Ran git diff -- macos-app/ContentView.swift macos-app/LocalAPIServer.swift
  └ diff --git a/macos-app/ContentView.swift b/macos-app/ContentView.swift
    index 3905db1..6be9e12 100644
    … +151 lines (ctrl + t to view transcript)
             arrays = record.arrays
             error = record.error

there's no need for this. Don't do git status, don't do git diff. Don't do xcodebuild.
